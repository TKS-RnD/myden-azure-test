<#
.SYNOPSIS
    Manages Azure Data Disks and Temporary Storage: cleanup, preparation, and mounting.

.DESCRIPTION
    1. InitialCleanup: Resets data drives, moves CD-ROM to W:, and unmounts Temp storage.
    2. DrivePrepare: Initializes RAW disks and formats them without mounting.
    3. DriveMount: Mounts data disks and reassigns Temp storage.

    TAG FORMAT:
    The script uses an Azure VM tag (defined by $DataDiskLunsTagName) to map LUNs to drive letters.
    The tag value should be a semicolon-separated list of pairs.
    Each pair can be in the format 'LUN:DriveLetter' or 'DriveLetter:LUN'.
    Example values:
    - "10:F;11:G"
    - "F:10;G:11"
    - "10:F"
#>

param(
    [Parameter(Mandatory = $false)]
    [bool]$InitialCleanup = $true,

    [Parameter(Mandatory = $false)]
    [bool]$DrivePrepare = $true,

    [Parameter(Mandatory = $false)]
    [bool]$DriveMount = $true
)

$DataDiskLunsTagName = 'DataDiskLuns'

# This function returns the Tag Data which indicates the disks to map (LUN:Disk, LUN:DISK..)
function Get-AzureDiskMetadata {
    [CmdletBinding()]
    param()

    $Headers = @{ "Metadata" = "true" }
    $Uri = "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"

    try {
        $Metadata = Invoke-RestMethod -Headers $Headers -Uri $Uri -Method Get -ErrorAction Stop
        $DataDiskLunsTagValue = ($Metadata.tagsList | Where-Object { $_.name -eq $DataDiskLunsTagName }).value
        if ($null -eq $DataDiskLunsTagValue) {
            Write-Warning "$DataDiskLunsTagName tag not found in IMDS metadata."
            return @()
        }
        Write-Verbose "Found $DataDiskLunsTagName tag value: $DataDiskLunsTagValue"

        # Format: "10:F;11:G" or "F:10;G:11"
        $Pairs = $DataDiskLunsTagValue -split ';'
        $Result = @()
        foreach ($Pair in $Pairs) {
            if ($Pair -match '^(\d+):([A-Za-z])$') {
                $Result += [PSCustomObject]@{
                    lun  = [int]$Matches[1]
                    driveLetter = $Matches[2].ToUpper()
                }
            }
            elseif ($Pair -match '^([A-Za-z]):(\d+)$') {
                $Result += [PSCustomObject]@{
                    lun  = [int]$Matches[2]
                    driveLetter = $Matches[1].ToUpper()
                }
            }
            else {
                Write-Warning "Disk mapping pair '$Pair' does not match expected format 'LUN:DriveLetter' or 'DriveLetter:LUN'"
            }
        }
        return $Result
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        Write-Error -Message "Failed to retrieve metadata from IMDS: $ErrorMessage"
        return $null
    }
}

# Azure attaches temporary disks to a VM. We need to know what that disk is. So that it can be disconnected and
# remounted in a different disk number.
function Get-TemporaryStorageDisk {
    [CmdletBinding()]
    param()

    # In Azure, the temporary storage is usually labeled "Temporary Storage" or "Resource Disk".
    $Disk = $null
    $Volume = Get-Volume | Where-Object { $_.FileSystemLabel -match "Temporary Storage|Resource Disk" }
    if ($null -ne $Volume) {
        $Partition = Get-Partition -DriveLetter $Volume.DriveLetter -ErrorAction SilentlyContinue
        if ($null -ne $Partition) {
            $Disk = Get-Disk -Number $Partition.DiskNumber -ErrorAction SilentlyContinue
        }
    }

    if ($null -eq $Disk) {
        # Fallback to look for a disk with the label if no drive letter is assigned
        $Partition = Get-Partition                                                     |
                     Where-Object { $_.Type -ne 'Reserved' -and $_.Type -ne 'System' } |
                     Where-Object {
                         (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -match "Temporary Storage|Resource Disk"
                     }
        if ($null -ne $Partition) {
            $Disk = Get-Disk -Number $Partition.DiskNumber -ErrorAction SilentlyContinue
        }
    }

    # Second fallback: check physical disks directly by model (often "Virtual Disk" or "Azure ICT")
    # and look for specific partition labels if Get-Volume didn't catch it
    if ($null -eq $Disk) {
        $Disks = Get-Disk | Where-Object { $_.BusType -eq 'SAS' -or $_.BusType -eq 'SATA' }
        foreach ($d in $Disks) {
            $labels = Get-Partition -DiskNumber $d.Number |
                      ForEach-Object {
                          (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel
                      }
            if ($labels -match "Temporary Storage|Resource Disk") {
                $Disk = $d
                break
            }
        }
    }

    if ($null -ne $Disk -and $Disk.OperationalStatus -eq 'Offline') {
        Write-Output "Bringing Temporary Storage Disk Online"
        $Disk | Set-Disk -IsOffline $false
        $Disk = Get-Disk -Number $Disk.Number
    }
    return $Disk
}

# Given a LUN ID in number, returns the corresponding disk object.
function Get-PhysicalDiskByLun {
    param([int]$LunId)
    $Disk = Get-Disk | Where-Object { $_.Location -match "LUN\s+$LunId(\s|$)" }
    if ($null -ne $Disk -and $Disk.OperationalStatus -eq 'Offline') {
        Write-Output "Bringing Disk (LUN $LunId) Online"
        $Disk | Set-Disk -IsOffline $false
        $Disk = Get-Disk -Number $Disk.Number
    }
    return $Disk
}

# Given a disk object removes all the access paths to which it is connected or attached to.
function Clear-DiskAccessPaths {
    param($Disk)
    if ($null -eq $Disk) { return }

    $Partitions = Get-Partition -DiskNumber $Disk.Number | Where-Object { $_.Type -ne 'Reserved' -and $_.Type -ne 'System' }
    foreach ($Partition in $Partitions) {
        try {
            # Always refresh the partition object to get latest access paths
            $CurrentPartition = Get-Partition -DiskNumber $Partition.DiskNumber -PartitionNumber $Partition.PartitionNumber

            # Remove Drive Letter if present
            if ($CurrentPartition.DriveLetter -ne [char]0) {
                Write-Verbose "Removing drive letter $($CurrentPartition.DriveLetter): from Disk $($Disk.Number) Partition $($CurrentPartition.PartitionNumber)"
                $CurrentPartition | Remove-PartitionAccessPath -DriveLetter $CurrentPartition.DriveLetter -ErrorAction SilentlyContinue
            }

            # Remove other access paths (mount points)
            foreach ($Path in $CurrentPartition.AccessPaths) {
                if ($Path -notmatch '^\\\\\?\\Volume\{') {
                    Write-Verbose "Removing access path: $Path from Disk $($Disk.Number) Partition $($CurrentPartition.PartitionNumber)"
                    $CurrentPartition | Remove-PartitionAccessPath -AccessPath $Path -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            Write-Warning "Failed to clear access paths from Disk $($Disk.Number) Partition $($Partition.PartitionNumber): $($_.Exception.Message)"
        }
    }
}

# A Partition volume in a disk may take a long time to come up. So wait accordingly.
function Wait-ForVolume {
    param($Partition)
    $Volume = $null
    for ($i = 0; $i -lt 300; $i++) {
        $Volume = Get-Volume -Partition $Partition -ErrorAction SilentlyContinue
        if ($null -ne $Volume) { break }
        Start-Sleep -Seconds 1
    }
    return $Volume
}

# Given a Partition in a Disk, Attach it to the Drive Letter.
function Set-PartitionDriveLetter {
    param(
        $Partition,
        [char]$DriveLetter,
        [string]$Description
    )
    if ($null -eq $Partition) { return $false }

    Write-Output "Mounting $Description to ${DriveLetter}:"
    try {
        Set-Partition -DiskNumber $Partition.DiskNumber -PartitionNumber $Partition.PartitionNumber -NewDriveLetter $DriveLetter -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "Failed to mount $Description to ${DriveLetter}: $($_.Exception.Message)"
        return $false
    }
}

# Given a Disk, get it's data partition.
function Get-DataPartition {
    param($Disk)
    if ($null -eq $Disk) { return $null }

    # Refresh disk to ensure we see the latest partition table
    $Disk | Update-Disk

    return Get-Partition -DiskNumber $Disk.Number |
        Where-Object { $_.Type -ne 'Reserved' -and $_.Type -ne 'System' -and $_.Type -ne 'Recovery' } |
        Sort-Object PartitionNumber |
        Select-Object -First 1
}

# Initialize and format a given disk with a data partition that can be mounted and attached to a disk number.
function Initialize-AndFormatDisk {
    param(
        $Disk,
        [string]$Label
    )
    if ($null -eq $Disk) { return }

    if ($Disk.PartitionStyle -eq 'Raw') {
        Write-Output "Initializing Disk $($Disk.Number) as GPT"
        $Disk | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -UseMaximumSize > $null
    }

    $Partition = Get-DataPartition -Disk $Disk
    if ($null -eq $Partition) {
        Write-Output "No data partition found on Disk $($Disk.Number). Creating new partition."
        $Partition = $Disk | New-Partition -UseMaximumSize
    }

    if ($null -ne $Partition) {
        $Volume = Wait-ForVolume -Partition $Partition
        if ($null -eq $Volume -or [string]::IsNullOrWhiteSpace($Volume.FileSystem) -or $Volume.FileSystem -eq "Unknown") {
            Write-Output "Formatting partition on Disk $($Disk.Number) with label '$Label'"
            Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel $Label -Confirm:$false
        }
    }
}

# First Step - Cleanup of existing environment:
# 1. Remove all drive assignments of mounted data disks.
# 2. Move CDROM Drive to W:
# 3. Unmount Azure Temp storage disk.
function Invoke-InitialCleanup {
    Write-Output "Starting Initial Cleanup stage..."

    # 1. Reset any connected data drives by removing Drive assignment
    $Metadata = Get-AzureDiskMetadata
    if ($null -ne $Metadata) {
        foreach ($DiskInfo in $Metadata) {
            $Disk = Get-PhysicalDiskByLun -LunId $DiskInfo.lun
            if ($null -ne $Disk) {
                Write-Output "Clearing access paths from Data Disk (LUN $($DiskInfo.lun))"
                Clear-DiskAccessPaths -Disk $Disk
            }
        }
    }

    # 2. If a CDROM drive is present move it to W:
    $CdRoms = Get-CimInstance -ClassName Win32_Volume -Filter "DriveType = 5" # 5 is CD-ROM
    foreach ($CdRom in $CdRoms) {
        if ($CdRom.DriveLetter -ne "W:") {
            Write-Output "Moving CD-ROM from $($CdRom.DriveLetter) to W:"
            $CdRom.DriveLetter = "W:"
            Set-CimInstance -CimInstance $CdRom
        }
    }

    # 3. If an azure temp storage is found, unmount it
    $TempDisk = Get-TemporaryStorageDisk
    if ($null -ne $TempDisk) {
        Write-Output "Clearing access paths from Azure Temp Storage"
        Clear-DiskAccessPaths -Disk $TempDisk
    }
}

# Drive Preparation Stage:
# 1. Format and Create data partitions on the connected data drives.
# 2. Format and Create data partitions on the temporary storage disk.
function Invoke-DrivePrepare {
    Write-Output "Starting Drive Preparation stage..."
    $Metadata = Get-AzureDiskMetadata
    if ($null -eq $Metadata) { return }

    foreach ($DiskInfo in $Metadata) {
        $Disk = Get-PhysicalDiskByLun -LunId $DiskInfo.lun
        if ($null -eq $Disk) {
            Write-Warning "Could not find physical disk for LUN $($DiskInfo.lun)"
            continue
        }

        Initialize-AndFormatDisk -Disk $Disk -Label "DataDisk_$($DiskInfo.lun)"

        # Ensure it's not mounted
        Clear-DiskAccessPaths -Disk $Disk
    }

    # Preparation for Temporary Storage
    $TempDisk = Get-TemporaryStorageDisk
    if ($null -ne $TempDisk) {
        Initialize-AndFormatDisk -Disk $TempDisk -Label "Temporary Storage"
        Clear-DiskAccessPaths -Disk $TempDisk
    }
}

# Final Stage:
# 1. Mount data drives.
# 2. Mount temporary disk in the drive letter after the data drives.
function Invoke-DriveMount {
    Write-Output "Starting Drive Mount stage..."
    $Metadata = Get-AzureDiskMetadata
    if ($null -eq $Metadata) { return }

    $UsedLetters = @()
    foreach ($DiskInfo in $Metadata) {
        $Disk = Get-PhysicalDiskByLun -LunId $DiskInfo.lun
        if ($null -ne $Disk) {
            $Partition = Get-DataPartition -Disk $Disk
            if ($null -ne $Partition) {
                if (Set-PartitionDriveLetter -Partition $Partition -DriveLetter $DiskInfo.driveLetter -Description "LUN $($DiskInfo.lun)") {
                    $UsedLetters += $DiskInfo.driveLetter
                }
            }
        }
    }

    # Mount Azure Temp drive next to last data drive letter
    $TempDisk = Get-TemporaryStorageDisk
    if ($null -ne $TempDisk) {
        $LastLetter = ($UsedLetters | Sort-Object | Select-Object -Last 1)
        if ($null -eq $LastLetter) {
            # Fallback if no data disks were mounted
            $LastLetter = 'C'
        }

        $NextLetter = [char]([int][char]$LastLetter + 1)
        if ($NextLetter -gt [char]'Z') {
            Write-Error "No available drive letter for Temporary Storage."
        }
        else {
            $TempPartition = Get-DataPartition -Disk $TempDisk
            Set-PartitionDriveLetter -Partition $TempPartition -DriveLetter $NextLetter -Description "Azure Temp Storage"
        }
    }
}

# Main Execution. Invoke all 3 stages are as desired by the user.
if ($InitialCleanup) { Invoke-InitialCleanup }
if ($DrivePrepare)   { Invoke-DrivePrepare }
if ($DriveMount)     { Invoke-DriveMount }
