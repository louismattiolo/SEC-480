# exampel .\clone.ps1 -SourceVM "server.2019.base" -Snapshot "Base" -NewVMName "server.2019.v2"
# usage: .\clone.ps1 [-SourceVM <name>] [-Snapshot <name>] [-NewVMName <name>] [-vServer <host>] [-VMHost <host>] [-Datastore <name>] [-NewSnapshot <name>]

# params to take in change if needed 
# source vm snapshot and newvm left blank so you can specify in command 
param(
    [string]$vServer     = "vcenter.louis.local",
    [string]$SourceVM    = "",
    [string]$Snapshot    = "",
    [string]$VMHost      = "192.168.3.220",
    [string]$Datastore   = "datastore2",
    [string]$NewVMName   = "",
    [string]$NewSnapshot = "Base"
)

# require these before doing anything prompts if not  
if (-not $SourceVM)  { $SourceVM  = Read-Host "Source VM name" }
if (-not $Snapshot)  { $Snapshot  = Read-Host "Snapshot name" }
if (-not $NewVMName) { $NewVMName = Read-Host "New VM name" }

# gathers objects 
Connect-VIServer $vServer -Credential (Get-Credential)
$vm       = Get-VM -Name $SourceVM
$snap     = Get-Snapshot -VM $vm -Name $Snapshot
$vmhost   = Get-VMHost -Name $VMHost
$ds       = Get-Datastore -Name $Datastore
$linkName = "$($vm.Name).linked"

# creates new linked clone then builds full vm then removes the linked one

Write-Host "Creating linked clone: $linkName"
$linkedVM = New-VM -LinkedClone -Name $linkName -VM $vm -ReferenceSnapshot $snap -VMHost $vmhost -Datastore $ds
Write-Host "Creating full VM: $NewVMName"
$newVM = New-VM -Name $NewVMName -VM $linkedVM -VMHost $vmhost -Datastore $ds
Write-Host "Snapshotting: $NewSnapshot"
$newVM | New-Snapshot -Name $NewSnapshot
Write-Host "Cleaning up linked clone"
$linkedVM | Remove-VM -Confirm:$false
Write-Host "Done. VM '$NewVMName' is ready."
