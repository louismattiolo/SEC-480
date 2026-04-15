function 480Banner()
{
    Write-Host "Hello SYS480 Devops"
}



# 480Connect - connects to a vCenter server
# vCenter will handle the error if any
Function 480Connect([string] $server)
{
    $conn = $global:DefaultVIServer
    if($conn) {
       
        $msg = "Already connected to: {0}" -f $conn
        Write-Host -ForegroundColor Green $msg
    }
    else {
        
        $conn = Connect-VIServer -Server $server
    }
}



# reads JSON config file and returns it as an object
Function Get-480Config([string] $config_path)
{
    Write-Host "Reading " $config_path
    $conf = $null
    if (Test-Path $config_path)
    {
        $conf = (Get-Content -Raw -Path $config_path | ConvertFrom-Json)
        $msg = "Using config from: {0}" -f $config_path
        Write-Host -ForegroundColor Green $msg
    }
    else
    {
        Write-Host -ForegroundColor Red "No Configuration found at $config_path"
    }
    return $conf
}


# lists all VMs in a given folder and lets the user pick one by index
Function Select-VM([string] $folder)
{
    $vms = Get-VM -Location $folder
    $index = 1
    foreach ($vm in $vms)
    {
        Write-Host [$index] $vm.name
        $index += 1
    }
    $pick_index = Read-Host "Which index number [x] do you want to pick?"

    if (-not ($pick_index -match '^\d+$') -or [int]$pick_index -lt 1 -or [int]$pick_index -gt $vms.Count)
    {
        Write-Host -ForegroundColor Red "Invalid selection. Please enter a number between 1 and $($vms.Count)."
        return $null
    }

    $selected_vm = $vms[[int]$pick_index - 1]
    Write-Host "You picked " $selected_vm.name
    return $selected_vm
}




# lists all snapshots on a given VM and lets the user pick one by index 
Function Select-Snapshot([object] $vm)
{
    $snapshots = Get-Snapshot -VM $vm
    if (-not $snapshots)
    {
        Write-Host -ForegroundColor Red "No snapshots found on VM '$($vm.name)'."
        return $null
    }
    $index = 1
    foreach ($snap in $snapshots)
    {
        Write-Host [$index] $snap.name
        $index += 1
    }
    $pick_index = Read-Host "Which snapshot do you want to clone from?"

    if (-not ($pick_index -match '^\d+$') -or [int]$pick_index -lt 1 -or [int]$pick_index -gt $snapshots.Count)
    {
        Write-Host -ForegroundColor Red "Invalid selection. Please enter a number between 1 and $($snapshots.Count)."
        return $null
    }

    $selected_snap = $snapshots[[int]$pick_index - 1]
    Write-Host "You picked " $selected_snap.name
    return $selected_snap
}




# New-LinkedClone creates a linked clone from a snapshot of an existing VM
Function New-LinkedClone([object] $vm, [object] $snapshot, [string] $clone_name, [string] $esxi_host, [string] $datastore)
{
    
    if (-not $clone_name) { $clone_name = Read-Host "Enter a name for the new linked clone" }
    if (-not $esxi_host)  { $esxi_host  = Read-Host "Enter the ESXi host (IP or hostname)" }
    if (-not $datastore)  { $datastore  = Read-Host "Enter the datastore name" }

    $vmhost = Get-VMHost -Name $esxi_host
    $ds     = Get-Datastore -Name $datastore

    Write-Host -ForegroundColor Yellow "Creating linked clone '$clone_name'..."
    $linked_clone = New-VM -Name $clone_name -VM $vm -ReferenceSnapshot $snapshot -VMHost $vmhost -Datastore $ds -LinkedClone
    Write-Host -ForegroundColor Green "Linked clone '$clone_name' created successfully."
    return $linked_clone
}



# New-FullClone creates a full clone of a VM from a snapshot
Function New-FullClone([object] $vm, [object] $snapshot, [string] $clone_name, [string] $esxi_host, [string] $datastore)
{
    if (-not $clone_name) { $clone_name = Read-Host "Enter a name for the new full clone" }
    if (-not $esxi_host)  { $esxi_host  = Read-Host "Enter the ESXi host (IP or hostname)" }
    if (-not $datastore)  { $datastore  = Read-Host "Enter the datastore name" }

    $vmhost = Get-VMHost -Name $esxi_host
    $ds     = Get-Datastore -Name $datastore

    $temp_name = "temp-linked-clone"
    Write-Host -ForegroundColor Yellow "Creating temporary linked clone '$temp_name'..."
    $temp_clone = New-VM -Name $temp_name -VM $vm -ReferenceSnapshot $snapshot -VMHost $vmhost -Datastore $ds -LinkedClone

    try
    {
        Write-Host -ForegroundColor Yellow "Creating full clone '$clone_name'..."
        $full_clone = New-VM -Name $clone_name -VM $temp_clone -VMHost $vmhost -Datastore $ds

        Write-Host -ForegroundColor Yellow "Removing temporary linked clone..."
        Remove-VM -VM $temp_clone -DeletePermanently -Confirm:$false

        Write-Host -ForegroundColor Green "Full clone '$clone_name' created successfully."
        return $full_clone
    }
    catch
    {
        Write-Host -ForegroundColor Red "Error creating full clone: $_"
        Write-Host -ForegroundColor Yellow "Cleaning up temporary linked clone '$temp_name'..."
        Remove-VM -VM $temp_clone -DeletePermanently -Confirm:$false
    }
}


# Get-IP - picks a single VM and shows its IP and MAC
Function Get-IP()
{
    $vms = Get-VM
    $index = 1
    foreach($i in $vms)
    {
        Write-Host [$index] $i.Name
        $index += 1
    }
    $pick   = Read-Host "What VM do you want to get the IP for? Enter the index number [x]"
    $picked = $vms[$pick - 1]
    Write-Host "Selected VM: " $picked.Name
 
    $mac = Get-NetworkAdapter -VM $picked | Select-Object -First 1
    $ip  = $picked.guest.ipaddress[0]
 
    Write-Host "hostname = " $picked.Name
    Write-Host "ip       = " $ip
    Write-Host "mac      = " $mac.MacAddress
}


# Get-IPs - shows IP and MAC for all VMs matching a name pattern
Function Get-IPs([string] $pattern)
{
    if ($pattern)
    {
        $vms = Get-VM | Where-Object { $_.Name -like "*$pattern*" }
    }
    else
    {
        $vms = Get-VM
    }

    if (-not $vms)
    {
        Write-Host -ForegroundColor Red "No VMs found matching pattern '$pattern'."
        return
    }

    Write-Host -ForegroundColor Cyan "`n{0,-20} {1,-18} {2,-20}" -f "Hostname", "IP Address", "MAC Address"
    Write-Host -ForegroundColor Cyan ("{0,-20} {1,-18} {2,-20}" -f "--------", "----------", "-----------")

    foreach ($vm in $vms)
    {
        $mac = (Get-NetworkAdapter -VM $vm | Select-Object -First 1).MacAddress
        $ip  = $vm.guest.ipaddress[0]
        if (-not $ip) { $ip = "N/A (powered off or no tools)" }
        Write-Host ("{0,-20} {1,-18} {2,-20}" -f $vm.Name, $ip, $mac)
    }
}


# New-Network asks for a name and creates a new vSwitch + port group on the ESXi host
Function New-Network([string] $esxi_host)
{
    $name    = Read-Host "What would you like to call this new network?"
    $vswitch = New-VirtualSwitch -VMHost $esxi_host -Name $name
    New-VirtualPortGroup -VirtualSwitch $vswitch -Name $name
    Write-Host -ForegroundColor Green "Network '$name' created."
}


# StartaVM lists all VMs and lets you pick one to power on
Function StartaVM()
{
    $vms = Get-VM
    $index = 1
    foreach($i in $vms)
    {
        Write-Host [$index] $i.Name
        $index += 1
    }
    $pick   = Read-Host "What VM do you want to power on? Enter the index number [x]"
    $turnon = $vms[$pick - 1]
    Write-Host "Selected VM: " $turnon.Name
    Start-VM -VM $turnon.Name
}

 
# StoppaVM lists all VMs and lets you pick one to power off
Function StoppaVM()
{
    $vms = Get-VM
    $index = 1
    foreach($i in $vms)
    {
        Write-Host [$index] $i.Name
        $index += 1
    }
    $pick    = Read-Host "What VM do you want to power off? Enter the index number [x]"
    $turnoff = $vms[$pick - 1]
    Write-Host "Selected VM: " $turnoff.Name
    Stop-VM -VM $turnoff.Name
}

# Set-Network lists VMs, then adapters, then available networks and lets you pick
Function Set-Network()
{
    $vms = Get-VM
    $index = 1
    foreach($i in $vms)
    {
        Write-Host [$index] $i.Name
        $index += 1
    }
    $pick   = Read-Host "What VM do you want to set the network for? Enter the index number [x]"
    $picked = $vms[$pick - 1]
    Write-Host "Selected VM: " $picked.Name
 
    $adapters = Get-NetworkAdapter -VM $picked
    $index = 1
    foreach($i in $adapters)
    {
        Write-Host "[$index] name: $($i.Name)  network: $($i.NetworkName)  mac: $($i.MacAddress)"
        $index += 1
    }
    $adapterpick = Read-Host "Which network adapter do you want to update?"
    $adapter     = $adapters[$adapterpick - 1]
 
    $networks = Get-VirtualNetwork
    $index = 1
    foreach($i in $networks)
    {
        Write-Host [$index] $i.Name
        $index += 1
    }
    $netpick = Read-Host "What network do you want to connect the adapter to? Enter the index number [x]"
    $net     = $networks[$netpick - 1]
 
    Set-NetworkAdapter -NetworkAdapter $adapter -NetworkName $net.Name -Confirm:$false
    Write-Host "Updated $($adapter.Name) on $($picked.Name) to $($net.Name)"
}