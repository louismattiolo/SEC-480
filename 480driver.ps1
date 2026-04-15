Import-Module '/home/louis/SEC-480/modules/480-utils/480-utils.psm1' -Force

480Banner

$conf = Get-480Config -config_path "/home/louis/SEC-480/480.json"
480Connect -server $conf.vcenter_server

if (-not $global:DefaultVIServer) {
    Write-Host -ForegroundColor Red "Failed to connect to vCenter. Exiting."
    exit
}

# --- Create 3 Rocky linked clones on blue20-lan ---
$rocky_base = Get-VM -Name "Rocky"
$rocky_snap = Get-Snapshot -VM $rocky_base -Name "Base"
$rocky_clones = @("rocky-1", "rocky-2", "rocky-3")

foreach ($clone_name in $rocky_clones)
{
    $exists = Get-VM -Name $clone_name -ErrorAction SilentlyContinue
    if ($exists) {
        Write-Host -ForegroundColor Yellow "$clone_name already exists, skipping."
    } else {
        $clone = New-LinkedClone -vm $rocky_base -snapshot $rocky_snap -clone_name $clone_name -esxi_host $conf.esxi_host -datastore $conf.datastore
        $adapter = Get-NetworkAdapter -VM $clone
        Set-NetworkAdapter -NetworkAdapter $adapter -NetworkName "blue20-lan" -Confirm:$false
        Write-Host -ForegroundColor Green "$clone_name network set to blue20-lan"
    }
    $vm = Get-VM -Name $clone_name
    if ($vm.PowerState -ne "PoweredOn") {
        Write-Host -ForegroundColor Yellow "Powering on $clone_name..."
        Start-VM -VM $vm | Out-Null
    }
}

# --- Create 2 Ubuntu linked clones on blue20-lan ---
$ubuntu_base = Get-VM -Name "ubuntu-server"
$ubuntu_snap = Get-Snapshot -VM $ubuntu_base -Name "Base"
$ubuntu_clones = @("ubuntu-1", "ubuntu-2")

foreach ($clone_name in $ubuntu_clones)
{
    $exists = Get-VM -Name $clone_name -ErrorAction SilentlyContinue
    if ($exists) {
        Write-Host -ForegroundColor Yellow "$clone_name already exists, skipping."
    } else {
        $clone = New-LinkedClone -vm $ubuntu_base -snapshot $ubuntu_snap -clone_name $clone_name -esxi_host $conf.esxi_host -datastore $conf.datastore
        $adapter = Get-NetworkAdapter -VM $clone
        Set-NetworkAdapter -NetworkAdapter $adapter -NetworkName "blue20-lan" -Confirm:$false
        Write-Host -ForegroundColor Green "$clone_name network set to blue20-lan"
    }
    $vm = Get-VM -Name $clone_name
    if ($vm.PowerState -ne "PoweredOn") {
        Write-Host -ForegroundColor Yellow "Powering on $clone_name..."
        Start-VM -VM $vm | Out-Null
    }
}

Write-Host -ForegroundColor Cyan "`nWaiting 30 seconds for VMs to boot..."
Start-Sleep -Seconds 30

Write-Host -ForegroundColor Cyan "`n--- Rocky IPs ---"
Get-IPs -pattern "rocky"

Write-Host -ForegroundColor Cyan "`n--- Ubuntu IPs ---"
Get-IPs -pattern "ubuntu"