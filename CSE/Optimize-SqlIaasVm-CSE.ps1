[CmdletBinding()]

param (
    
    # Number of data disks
    [Parameter(Mandatory = $true)]
    [int]
    $NumberOfDataDisks,
    
    # If present, all data disks will be striped in a storage pool
    [Parameter(Mandatory = $false)]
    [switch]
    $StripeDataDisks,

    # Number of data disks
    [Parameter(Mandatory = $true)]
    [int]
    $NumberOfLogDisks,
    
    # If present, all data disks will be striped in a storage pool
    [Parameter(Mandatory = $false)]
    [switch]
    $StripeLogDisks,

    # Number of additional disks
    [Parameter(Mandatory = $true)]
    [int]
    $NumberOfAdditionalDisks,
    
    # Type of workload
    [Parameter(Mandatory = $false)]
    [ValidateSet("OLTP","DW", "Generic")]
    [string]
    $WorkloadType = "OLTP",

    # SysAdmin
    [Parameter(Mandatory = $true)]
    [string]
    $SysAdminUsername,

    # SysAdmin Password
    [Parameter(Mandatory = $true)]
    [string]
    $SysAdminPassword

)

Import-Module .\Optimize-SqlIaasVm-CSE.psm1

$ErrorActionPreference = "Stop"

$CurrentDriveLetter = "F"

if($NumberOfDataDisks -ge 1) {
    ### Create storage configuration for data disks ###
    # Define an array of LUN dedicated to data disks, starting from 0 to $NumberOfDataDisks - 1
    $DataLun = @(0..$($NumberOfDataDisks - 1))

    if($StripeDataDisks -and $NumberOfDataDisks -gt 1) {

        try {
        
            # Create a SQL Optimized striped storage pool 
            New-StoragePoolForSql -LUN $DataLun `
                -StoragePoolFriendlyName "SqlDataPool" `
                -VirtualDiskFriendlyName "SqlDataVdisk" `
                -VolumeLabel "SQLDataDisk" `
                -FileSystem NTFS `
                -DriveLetter $([char]$CurrentDriveLetter) `
                -WorkLoadType $WorkloadType | Out-Null

            Write-Output "Storage pool for SQL Data created with LUN $($DataLun -join ",")"
        }
        catch {
            Write-Output "Error while creating data storage pool:"
            Throw $_
        }

        While(!(Test-Path "$([char]$CurrentDriveLetter):\")) {
            Update-HostStorageCache
            Update-StorageProviderCache
        }

        $DataPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLData"

        if($NumberOfLogDisks -eq 0) {
            $LogPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLLog"
            $ErrorLogPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLErrorLog"
            if($NumberOfAdditionalDisks -eq 0) {
                $BackupPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLBackup"
            }
        }

        # Increment drive letter for next drives
        [char]([int][char]$CurrentDriveLetter)++ | Out-Null

    } else {

        
        # Get single disks dedicated to data
        $SingleDisk = Get-PhysicalDiskExt | Where-Object {$_.InterfaceType -eq 'SCSI' -and $_.ScsiLun -In $DataLun } | Get-Disk | Sort-Object Number

        $i = 1
        $SingleDisk | ForEach-Object {

            try {
                # Create a new optimized single disk
                New-SingleDiskForSql -Disk $_ `
                    -VolumeLabel "SqlDataDisk$i" `
                    -FileSystem NTFS `
                    -DriveLetter $([char]$CurrentDriveLetter) `
                    -Force `
                    -SkipClearDisk | Out-Null

                Write-Output "Disk $($_.PhysicalLocation) configured"
            }
            catch {
                Write-Output "Error while creating volume on disk $($_.PhysicalLocation):"
                Throw $_
            }

            While(!(Test-Path "$([char]$CurrentDriveLetter):\")) {
                Update-HostStorageCache
            }

            if($i = 1) {
                $DataPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLData"
            } else {
                New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLData" | Out-Null
            }

            if($NumberOfLogDisks -eq 0) {
                $LogPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLLog"
                $ErrorLogPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLErrorLog"
                if($NumberOfAdditionalDisks -eq 0) {
                    $BackupPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLBackup"
                }
            }

            # Increment drive letter for next drives
            [char]([int][char]$CurrentDriveLetter)++ | Out-Null
            $i++ | Out-Null
        }
    }
}

### Create storage configuration for log disks ###
if($NumberOfLogDisks -ge 1) {
    # Define an array of LUN dedicated to log disks, starting from $NumberOfDataDisks to ($NumberOfDataDisks + $NumberOfLogDisks - 1)
    $LogLun = @(($NumberOfDataDisks)..($NumberOfDataDisks + $NumberOfLogDisks - 1))

    if($StripeLogDisks -and $NumberOfLogDisks -gt 1) {
        
        try {
            # Create a SQL Optimized striped storage pool 
            New-StoragePoolForSql -LUN $LogLun `
                -StoragePoolFriendlyName "SqlLogPool" `
                -VirtualDiskFriendlyName "SqlLogVdisk" `
                -VolumeLabel "SQLLogDisk" `
                -FileSystem NTFS `
                -DriveLetter $([char]$CurrentDriveLetter) `
                -WorkLoadType $WorkloadType | Out-Null

            Write-Output "Storage pool for SQL Log created with LUN $($DataLun -join ",")"
        }
        catch {
            Write-Output "Error while creating data storage pool:"
            Throw $_
        }
 

        While(!(Test-Path "$([char]$CurrentDriveLetter):\")) {
            Update-HostStorageCache
            Update-StorageProviderCache
        }

        $LogPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLLog"
        $ErrorLogPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLErrorLog"

        if($NumberOfAdditionalDisks -eq 0) {
            $BackupPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLBackup"
        }

        # Increment drive letter for next drives
        [char]([int][char]$CurrentDriveLetter)++ | Out-Null

    } else {

        # Get single disks dedicated to log
        $SingleDisk = Get-PhysicalDiskExt | Where-Object {$_.InterfaceType -eq 'SCSI' -and $_.ScsiLun -In $LogLun } | Get-Disk | Sort-Object Number

        $i = 1
        $SingleDisk | ForEach-Object {

            
            try {

                # Create a new optimized single disk
                New-SingleDiskForSql -Disk $_ `
                    -VolumeLabel "SqlLogDisk$i" `
                    -FileSystem NTFS `
                    -DriveLetter $([char]$CurrentDriveLetter) `
                    -SkipClearDisk `
                    -Force | Out-Null
                
                Write-Output "Disk $($_.PhysicalLocation) configured"
            }
            catch {
                Write-Output "Error while creating volume on disk $($_.PhysicalLocation):"
                Throw $_
            }


            While(!(Test-Path "$([char]$CurrentDriveLetter):\")) {
                Update-HostStorageCache
            }

            
            if($i -eq 1) {
                $LogPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLLog"
                $ErrorLogPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLErrorLog"
                if($NumberOfAdditionalDisks -eq 0) {
                    $BackupPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLBackup"
                }
            } else {
                New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLLog" | Out-Null
            }

            # Increment drive letter for next drives
            [char]([int][char]$CurrentDriveLetter)++ | Out-Null
            $i++ | Out-Null
        }
    }
}

### Create storage configuration for additional disks ###
if($NumberOfAdditionalDisks -ge 1) {
    # Define an array of LUN dedicated to additional disks
    $DataAndLogDisks = $NumberOfDataDisks + $NumberOfLogDisks
    $AdditionalLun = @(($DataAndLogDisks)..($DataAndLogDisks + $NumberOfAdditionalDisks - 1))

    # Get single disks
    $SingleDisk = Get-PhysicalDiskExt | Where-Object {$_.InterfaceType -eq 'SCSI' -and $_.ScsiLun -In $AdditionalLun } | Get-Disk | Sort-Object Number

    $i = 1
    $SingleDisk | ForEach-Object {

        try {

            if($_.PartitionStyle -eq 'RAW') {
                $_ | Initialize-Disk -PartitionStyle GPT
            }
    
            $_ | New-Partition -UseMaximumSize -DriveLetter $([char]$CurrentDriveLetter) | Out-Null
            Format-Volume -DriveLetter $([char]$CurrentDriveLetter) `
                -FileSystem NTFS `
                -NewFileSystemLabel "Disk$i" `
                -Force `
                -Confirm:$false | Out-Null

            Write-Output "Disk $($_.PhysicalLocation) configured"
        }
        catch {
            Write-Output "Error while creating volume on disk $($_.PhysicalLocation)"
            Throw $_
        }
 
        if($i -eq 1) {
            While(!(Test-Path "$([char]$CurrentDriveLetter):\")) {
                Update-HostStorageCache
            }
            $BackupPath = New-SqlDirectory -DirectoryPath "$([char]$CurrentDriveLetter):\SQLBackup"
        }
        # Increment drive letter for next drives
        [char]([int][char]$CurrentDriveLetter)++ | Out-Null
        $i++ | Out-Null
    }
    
}

#Execution with different account
Enable-PSRemoting -Force
$DomainName = [System.String] (Get-CimInstance -ClassName Win32_ComputerSystem -Verbose:$false).Domain;
Enable-WSManCredSSP -Role Client -DelegateComputer "*.$DomainName" -Force
Enable-WSManCredSSP -Role Server -Force

$secpasswd = ConvertTo-SecureString $SysAdminPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("$env:COMPUTERNAME\$SysAdminUsername", $secpasswd)

$WorkingPath = (Push-Location -PassThru).Path

Invoke-Command -FilePath .\Optimized-SqlIaasVm-CSE-userImpersonation.ps1 `
    -ArgumentList ($WorkingPath, $DataPath, $LogPath, $BackupPath, $ErrorLogPath, $WorkloadType) `
    -Credential $credential `
    -ComputerName $env:COMPUTERNAME

Disable-WSManCredSSP -Role Client
Disable-WSManCredSSP -Role Server





