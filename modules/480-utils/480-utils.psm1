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
        # read the file and convert from JSON into a usable object
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

    # make sure the input is a number and falls within the valid range regex for this ^ is the start of the string \d+ is  one or more digits $ is end of the string 
    if (-not ($pick_index -match '^\d+$') -or [int]$pick_index -lt 1 -or [int]$pick_index -gt $vms.Count)
    {
        Write-Host -ForegroundColor Red "Invalid selection. Please enter a number between 1 and $($vms.Count)."
        return $null
    }

    # arrays are 0-indexed so subtract 1 from the user's pick
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

    # same as Select-VM
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
# parms come from the config file (480driver) any missing ones are prompted
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
# try/catch here bc if step 2 or 3 fails we need to clean up the temp clone, otherwise it gets left behind in vCenter as an orphaned VM 
Function New-FullClone([object] $vm, [object] $snapshot, [string] $clone_name, [string] $esxi_host, [string] $datastore)
{
   
    if (-not $clone_name) { $clone_name = Read-Host "Enter a name for the new full clone" }
    if (-not $esxi_host)  { $esxi_host  = Read-Host "Enter the ESXi host (IP or hostname)" }
    if (-not $datastore)  { $datastore  = Read-Host "Enter the datastore name" }

    $vmhost = Get-VMHost -Name $esxi_host
    $ds     = Get-Datastore -Name $datastore

    # create a temporary linked clone from the selected snapshot
    $temp_name = "temp-linked-clone"
    Write-Host -ForegroundColor Yellow "Creating temporary linked clone '$temp_name'..."
    $temp_clone = New-VM -Name $temp_name -VM $vm -ReferenceSnapshot $snapshot -VMHost $vmhost -Datastore $ds -LinkedClone

    try
    {
        # create the full clone from the temporary linked clone
        Write-Host -ForegroundColor Yellow "Creating full clone '$clone_name'..."
        $full_clone = New-VM -Name $clone_name -VM $temp_clone -VMHost $vmhost -Datastore $ds

        # remove the temporary linked clone, it is no longer needed
        Write-Host -ForegroundColor Yellow "Removing temporary linked clone..."
        Remove-VM -VM $temp_clone -DeletePermanently -Confirm:$false

        Write-Host -ForegroundColor Green "Full clone '$clone_name' created successfully."
        return $full_clone
    }
    catch
    {
        # if step 2 or 3 failed will clean up the temp clone so it does not get left behind in vCenter
        Write-Host -ForegroundColor Red "Error creating full clone: $_"
        Write-Host -ForegroundColor Yellow "Cleaning up temporary linked clone '$temp_name'..."
        Remove-VM -VM $temp_clone -DeletePermanently -Confirm:$false
    }
}