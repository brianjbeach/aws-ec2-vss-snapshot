#Taken from http://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-windows-volumes.html
Function Get-AttachedVolumes
{
    # List the Windows disks

    # Create a hash table that maps each device to a SCSI target
    $Map = @{"0" = '/dev/sda1'} 
    for($x = 1; $x -le 25; $x++) {$Map.add($x.ToString(), [String]::Format("xvd{0}",[char](97 + $x)))}
    for($x = 26; $x -le 51; $x++) {$Map.add($x.ToString(), [String]::Format("xvda{0}",[char](71 + $x)))}
    for($x = 52; $x -le 77; $x++) {$Map.add($x.ToString(), [String]::Format("xvdb{0}",[char](45 + $x)))}
    for($x = 78; $x -le 103; $x++) {$Map.add($x.ToString(), [String]::Format("xvdc{0}",[char](19 + $x)))}
    for($x = 104; $x -le 129; $x++) {$Map.add($x.ToString(), [String]::Format("xvdd{0}",[char]($x - 7)))}

    Try {
        # Use the metadata service to discover which instance the script is running on
        $InstanceId = (Invoke-WebRequest '169.254.169.254/latest/meta-data/instance-id').Content
        $AZ = (Invoke-WebRequest '169.254.169.254/latest/meta-data/placement/availability-zone').Content
        $Region = $AZ.Substring(0, $AZ.Length -1)

        #Get the volumes attached to this instance
        $BlockDeviceMappings = (Get-EC2Instance -Region $Region -Instance $InstanceId).Instances.BlockDeviceMappings
    }
    Catch
    {
        Write-Host "Could not access the AWS API, therefore, VolumeId is not available. 
    Verify that you provided your access keys."  -ForegroundColor Yellow
    }

    Get-WmiObject -Class Win32_DiskDrive | % {
        $Drive = $_
        # Find the partitions for this drive
        Get-WmiObject -Class Win32_DiskDriveToDiskPartition |  Where-Object {$_.Antecedent -eq $Drive.Path.Path} | %{
            $D2P = $_
            # Get details about each partition
            $Partition = Get-WmiObject -Class Win32_DiskPartition |  Where-Object {$_.Path.Path -eq $D2P.Dependent}
            # Find the drive that this partition is linked to
            $Disk = Get-WmiObject -Class Win32_LogicalDiskToPartition | Where-Object {$_.Antecedent -in $D2P.Dependent} | %{ 
                $L2P = $_
                #Get the drive letter for this partition, if there is one
                Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.Path.Path -in $L2P.Dependent}
            }
            $BlockDeviceMapping = $BlockDeviceMappings | Where-Object {$_.DeviceName -eq $Map[$Drive.SCSITargetId.ToString()]}
           
            # Display the information in a table
            New-Object PSObject -Property @{
                Device = $Map[$Drive.SCSITargetId.ToString()];
                Disk = [Int]::Parse($Partition.Name.Split(",")[0].Replace("Disk #",""));
                Boot = $Partition.BootPartition;
                Partition = [Int]::Parse($Partition.Name.Split(",")[1].Replace(" Partition #",""));
                SCSITarget = $Drive.SCSITargetId;
                DriveLetter = If($Disk -eq $NULL) {"NA"} else {$Disk.DeviceID};
                VolumeName = If($Disk -eq $NULL) {"NA"} else {$Disk.VolumeName};
                VolumeId = If($BlockDeviceMapping -eq $NULL) {"NA"} else {$BlockDeviceMapping.Ebs.VolumeId}
            }
        }
    } | Sort-Object Disk, Partition 
}

#Create a snapshot of each volume attached to this instances
Get-AttachedVolumes | Where-Object {$_.Boot -eq $false -and $_.VolumeId -ne $NULL} | % {
    Try {
        If($_.DriveLetter -eq 'NA') {throw "ERROR: This script does not support mount points!"}
        #Create a VSS Shadow Copy
        $Response = Invoke-Expression "vssadmin create shadow /for=$($_.DriveLetter)"
        #Parse the respone to get the Shadow Copy ID
        $ShadowId = ($Response | Select-String -Pattern 'Shadow Copy ID: {([0-9a-f-]*)}').Matches[0].Groups[1].Value
        #Create EC2 Snapshot and record meta-data so we can recreate it if needed
        New-EC2Snapshot -VolumeId $_.VolumeId -Description "VSS enabled snapshot; Device=$($_.Device); Drive Letter=$($_.DriveLetter); ShadowID=$ShadowId"
        #No need to wait for the snapshot to complete, we can remove the shadow copy
        Invoke-Expression "vssadmin delete shadows /Shadow='{$ShadowId}' /Quiet"
    }
    Catch
    {
        Write-Error $_
    }
} 


