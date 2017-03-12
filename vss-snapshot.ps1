$TempPath = [System.IO.Path]::GetTempPath()

@'
$SetId=$args[0]
#Use the Meta-data API to learn what instance and region this script is running in.
$InstanceId = (Invoke-WebRequest '169.254.169.254/latest/meta-data/instance-id' -UseBasicParsing).Content
$AZ = (Invoke-WebRequest '169.254.169.254/latest/meta-data/placement/availability-zone' -UseBasicParsing).Content
$Region = $AZ.Substring(0, $AZ.Length -1)
#Find all the volumes attached to this instance and create a Snapshot of each
$Volumes = (Get-EC2Instance -Region $Region -Instance $InstanceId).Instances.BlockDeviceMappings.Ebs.VolumeId
$Volumes | %{New-EC2Snapshot -Region $Region -VolumeId $_ -Description "Created by VSS-Snapshot; Instance=$InstanceId; VSSSetId=$SetId"}
'@ | Set-Content (Join-Path $TempPath 'CreateEBSSnapshots.ps1')

"Powershell.exe $(Join-Path $TempPath 'CreateEBSSnapshots.ps1') %1" | Set-Content (Join-Path $TempPath 'CreateEBSSnapshots.bat')

'SET CONTEXT CLIENTACCESSIBLE', 'BEGIN BACKUP' +
(Get-WmiObject Win32_Volume|%{"ADD VOLUME $($_.Name)"}) +
'CREATE', "EXEC $(Join-Path $TempPath 'CreateEBSSnapshots.bat') %VSS_SHADOW_SET%" + 
'DELETE SHADOWS SET %VSS_SHADOW_SET%', 'END BACKUP' + 
'EXIT' | Set-Content (Join-Path $TempPath 'CreateEBSSnapshots.dsh')

DISKSHADOW.EXE /s (Join-Path $TempPath 'CreateEBSSnapshots.dsh')

Remove-Item (Join-Path $TempPath 'CreateEBSSnapshots.dsh')
Remove-Item (Join-Path $TempPath 'CreateEBSSnapshots.ps1')
Remove-Item (Join-Path $TempPath 'CreateEBSSnapshots.bat')