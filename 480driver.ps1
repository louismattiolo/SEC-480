Import-Module '480-utils' -Force 
# call the banner function 
480Banner

$conf =  Get-480Config  -config_path "/home/louis/SEC-480/480.json"
480Connect -server $conf.vcenter_server
Write-Host "Selecting your VM"


# prompt for vm
$vm = Select-VM -folder $conf.vm_folder

if (-not $vm) {
    Write-Host -ForegroundColor Red "No VM selected. Exiting."
    exit
}


# prompt for snapshot 
$snapshot = Select-Snapshot -vm $vm

if (-not $snapshot) {
    Write-Host -ForegroundColor Red "No snapshot selected. Exiting."
    exit
}


# prompt for clone linked or full
$clone_type = Read-Host "What type of clone? Enter 'linked' or 'full'"

if ($clone_type -eq "linked") {
    New-LinkedClone -vm $vm -snapshot $snapshot -esxi_host $conf.esxi_host -datastore $conf.datastore

} elseif ($clone_type -eq "full") {
    New-FullClone -vm $vm -snapshot $snapshot -esxi_host $conf.esxi_host -datastore $conf.datastore

} else {
    Write-Host -ForegroundColor Red "Invalid clone type '$clone_type'. Enter 'linked' or 'full'."
}
