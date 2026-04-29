Import-Module '/home/louis/SEC-480/modules/480-utils/480-utils.psm1' -Force

480Banner

$conf = Get-480Config -config_path "/home/louis/SEC-480/480.json"
480Connect -server $conf.vcenter_server

if (-not $global:DefaultVIServer) {
    Write-Host -ForegroundColor Red "Failed to connect to vCenter. Exiting."
    exit
}

# -------- Config for dc-blue20 --------
$base_vm_name = "server.2019.gui.base"
$clone_name   = "dc-blue20"
$network      = "blue20-lan"
$static_ip    = "10.0.5.5"
$netmask      = "255.255.255.0"
$gateway      = "10.0.5.2"
$dns          = "8.8.8.8"          # pre-domain-promotion DNS; flips to self later
$guest_user   = "Administrator"
$interface    = "Ethernet0"

# -------- Prompt for guest password up front (SecureString) --------
$guest_pass = Read-Host "Enter the local Administrator password for $clone_name" -AsSecureString

# -------- Create the linked clone on blue20-lan --------
$base = Get-VM -Name $base_vm_name
$snap = Get-Snapshot -VM $base -Name $conf.snapshot_name

$exists = Get-VM -Name $clone_name -ErrorAction SilentlyContinue
if ($exists) {
    Write-Host -ForegroundColor Yellow "$clone_name already exists, skipping clone."
} else {
    $clone = New-LinkedClone `
        -vm         $base `
        -snapshot   $snap `
        -clone_name $clone_name `
        -esxi_host  $conf.esxi_host `
        -datastore  $conf.datastore

    $adapter = Get-NetworkAdapter -VM $clone
    Set-NetworkAdapter -NetworkAdapter $adapter -NetworkName $network -Confirm:$false
    Write-Host -ForegroundColor Green "$clone_name network set to $network"
}

# -------- Power on (if not already) --------
$vm = Get-VM -Name $clone_name
if ($vm.PowerState -ne "PoweredOn") {
    Write-Host -ForegroundColor Yellow "Powering on $clone_name..."
    Start-VM -VM $vm | Out-Null
}

# -------- Wait for VMware Tools so Invoke-VMScript can talk to the guest --------
Write-Host -ForegroundColor Cyan "Waiting for VMware Tools to come up on $clone_name..."
Wait-Tools -VM $vm -TimeoutSeconds 300 | Out-Null

# Windows also needs a moment after Tools reports ready before the login session
# is fully usable by Invoke-VMScript. Short sleep avoids the first call failing.
Start-Sleep -Seconds 30

# -------- Apply static IP via Invoke-VMScript --------
Set-WindowsIP `
    -VM            $vm `
    -GuestUser     $guest_user `
    -GuestPassword $guest_pass `
    -StaticIP      $static_ip `
    -Netmask       $netmask `
    -Gateway       $gateway `
    -DNS           $dns `
    -InterfaceName $interface

Write-Host -ForegroundColor Green "`n$clone_name should now be reachable at $static_ip"
Write-Host -ForegroundColor Cyan "Try: ssh Administrator@$static_ip (via your VyOS jump host)"