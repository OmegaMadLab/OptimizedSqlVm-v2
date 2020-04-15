#Checking for SQLPs module loaded
If (!(Get-module SqlPs)) {
    Push-Location
    Import-Module SqlPs -DisableNameChecking
    Pop-Location
}

# CSE function
# Create a new folder with full control ACE for default instance service SID (NT SERVICE\MSSQLSERVER)
function New-SqlDirectory {

    param (
        [Parameter(Mandatory=$true)]
        [string]$DirectoryPath
    )

    While(!(Test-Path $DirectoryPath.Split("\")[0])) { Start-Sleep -Milliseconds 500}

    $Directory = New-Item $DirectoryPath -ItemType Directory -Force

    $Username = "NT SERVICE\MSSQLSERVER"

    $Acl = (Get-Item $Directory.FullName).GetAccessControl('Access')
    $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Username, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $Acl.SetAccessRule($AccessRule)
    Set-Acl -path $Directory.FullName -AclObject $Acl

    #Return full path
    $Directory.FullName
}

# Storage Functions
function Get-PhysicalDiskExt {
    [CmdletBinding(DefaultParameterSetName='Disk')]
    [OutputType([psobject[]])]
    param (
        [parameter(Mandatory=$false, ParameterSetName='Disk')]
        [ValidateNotNullOrEmpty()]
        [int]
        $DiskNumber,

        [parameter(Mandatory=$false, ParameterSetName='Pipeline', ValueFromPipeline)]
        [CimInstance]
        $PipedObj
    )

    $OutObj = @()

    if($PsCmdLet.ParameterSetName -eq 'Pipeline') {
        $Disks = $PipedObj | Get-PhysicalDisk
    }
    else {
        if($DiskNumber)  {
            $Disks = Get-PhysicalDisk | Where-Object DeviceId -eq $DiskNumber
        }
        else {
            $Disks = Get-PhysicalDisk
        }
    }

    foreach($Disk in $Disks) {
        $WmiDiskDrive = Get-WmiObject -Class Win32_DiskDrive | Where-Object Index -eq $Disk.DeviceId

        $Properties = [ordered]@{
            InterfaceType = if(!$WmiDiskDrive.InterfaceType) { "StoragePool" } else { $WmiDiskDrive.InterfaceType }
            DeviceId = $Disk.DeviceId
            ScsiLun =$WmiDiskDrive.SCSILogicalUnit
            PhysicalLocation = $Disk.PhysicalLocation
            Size = [math]::Round($Disk.Size / 1GB, 2)
            CanPool = $Disk.CanPool
            CannotPoolReason = $Disk.CannotPoolReason
        }

        $OutObj += New-Object -Property $Properties -TypeName psobject

    }

    $OutObj

}

function New-StoragePoolForSql {
    param (
        [Parameter(Mandatory=$true)]
        [string]$StoragePoolFriendlyName,
        [string[]]$LUN,
        [string]$VirtualDiskFriendlyName = "$($FriendlyName)_VirtualDisk",
        [ValidateSet('OLTP','DW','Generic')]
        [string]$WorkLoadType = 'OLTP',
        [string]$DriveLetter,
        [string]$VolumeLabel = 'Data disk',
        [ValidateSet('NTFS','ReFS')]
        [string]$FileSystem = 'NTFS'
    )

    $storSubSys = Get-StorageSubSystem
    $DiskInfo = Get-PhysicalDiskExt | Where-Object ScsiLun -in $LUN
    $diskToPool = Get-PhysicalDisk -CanPool $true | Where-Object DeviceId -in $DiskInfo.DeviceId

    $StoragePool = New-StoragePool -StorageSubSystemUniqueId $storSubSys.UniqueId `
                        -FriendlyName $StoragePoolFriendlyName `
                        -PhysicalDisks $diskToPool

    New-VirtualDiskForSql -StoragePool $StoragePool `
                            -FriendlyName $VirtualDiskFriendlyName `
                            -DriveLetter $DriveLetter `
                            -VolumeLabel $VolumeLabel `
                            -FileSystem $FileSystem `
                            -WorkLoadType $WorkLoadType
}

function New-VirtualDiskForSql {
    param (
        [Parameter(Mandatory=$true)]
        [string]$FriendlyName,
        [Parameter(Mandatory=$true)]
        [ciminstance]$StoragePool,
        [ValidateSet('OLTP','DW','Generic')]
        [string]$WorkLoadType = 'OLTP',
        [string]$DriveLetter,
        [string]$VolumeLabel = 'Data disk',
        [ValidateSet('NTFS','ReFS')]
        [string]$FileSystem = 'NTFS'
    )

    
    $numberOfCols = $StoragePool | Get-PhysicalDisk | Measure-Object | Select-Object -ExpandProperty Count

    switch ($WorkLoadType) {
        "Generic" {
                    $interleaveKB='256'
                    $AllocationUnitSizeKB='4'
                    }
        "DW"      { 
                    $interleaveKB='256'
                    $AllocationUnitSizeKB='64'
                    }
        default   { 
                    $interleaveKB='64'
                    $AllocationUnitSizeKB='64'
                    }
    }

    $Vdisk = New-VirtualDisk -FriendlyName $FriendlyName `
                        -StoragePoolUniqueId $StoragePool.UniqueId `
                        -NumberOfColumns $numberOfCols `
                        -Interleave $([int]$interleaveKB*1024) `
                        -ResiliencySettingName Simple `
                        -UseMaximumSize

    Initialize-Disk -VirtualDisk $Vdisk -ErrorAction Ignore | Out-Null
    $disk = $Vdisk| Get-Disk 
    New-VolumeForSql -Disk $disk `
                        -DriveLetter $DriveLetter `
                        -VolumeLabel $VolumeLabel `
                        -FileSystem $FileSystem `
                        -AllocationUnitSizeKB $AllocationUnitSizeKB
}
function Clear-SingleDisk {
    param (
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [cimInstance]$Disk,
        [switch]$Force
    )

    $volRemoved = Remove-EveryVolume -Disk ($Disk | Get-Disk) -Force:$Force
    $volRemoved
}

Function Remove-EveryVolume {
    [CmdletBinding()]
    param (
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [cimInstance]$Disk,
        [switch]$Force
    )

    if(-not $Force) {
        $DriveLetters = $Disk | Get-Partition | Select-Object -ExpandProperty DriveLetter

        foreach($driveLetter in $driveLetters) {
            $confirm = Get-VolumeRemovalConfirm -DriveLetter $driveLetter
            if(-not $confirm) {
                Return $false
            }
        }
    }
    $Disk | Clear-Disk -RemoveData -Confirm:$Force
    Return $true
}

function New-SingleDiskForSql {
    param (
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [cimInstance]$Disk,
        [switch]$Force,
        [string]$DriveLetter,
        [string]$VolumeLabel = 'Data disk',
        [ValidateSet('NTFS','ReFS')]
        [string]$FileSystem = 'NTFS',
        [switch]$SkipClearDisk = $false
    )

    if($SkipClearDisk) {
        $cleared = $true
    } else {
        $cleared = Clear-SingleDisk -Disk $Disk -Force:$Force
    }
    if($cleared) {
        New-VolumeForSql -Disk $disk `
                    -DriveLetter $DriveLetter `
                    -VolumeLabel $VolumeLabel `
                    -FileSystem $FileSystem
        Return $true
    }
    Return $false
}
function New-VolumeForSql {
    param (
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [cimInstance]$Disk,
        [string]$DriveLetter,
        [string]$VolumeLabel = 'Data disk',
        [ValidateSet('NTFS','ReFS')]
        [string]$FileSystem = 'NTFS',
        [int]$AllocationUnitSizeKB = 64
    )

    if($Disk.PartitionStyle -eq 'RAW') {
        $Disk | Initialize-Disk -PartitionStyle GPT
    }

    if($DriveLetter) {
        $Disk | New-Partition -UseMaximumSize -DriveLetter $DriveLetter | Out-Null
        Format-VolumeForSql -DriveLetter $DriveLetter `
                            -Force `
                            -VolumeLabel $VolumeLabel `
                            -FileSystem $FileSystem `
                            -AllocationUnitSizeKB $AllocationUnitSizeKB
}
    else {
        $Disk | New-Partition -UseMaximumSize -AssignDriveLetter | Out-Null
        Format-VolumeForSql -DriveLetter ($Disk | Get-Partition).DriveLetter `
                            -Force `
                            -VolumeLabel $VolumeLabel `
                            -FileSystem $FileSystem `
                            -AllocationUnitSizeKB $AllocationUnitSizeKB
    }
    
}

function Format-VolumeForSql {
    param (
        [Parameter(
            Position=0, 
            Mandatory=$true, 
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)
        ]
        [string]$DriveLetter,
        [string]$NewDriveLetter,
        [string]$VolumeLabel = 'Data disk',
        [ValidateSet('NTFS','ReFS')]
        [string]$FileSystem,
        [int]$AllocationUnitSizeKB = 64,
        [switch]$Force = $false
    )

    if(-not $Force) {
        $confirm = Get-VolumeRemovalConfirm -DriveLetter $DriveLetter
        if(-not $confirm) {
            Return $false
        }
    }

    if(($NewDriveLetter) -and ($NewDriveLetter -ne $DriveLetter)) {
        Get-Volume -DriveLetter $DriveLetter | Get-Partition | Set-Partition -NewDriveLetter $NewDriveLetter
    }
    else {
        $NewDriveLetter = $DriveLetter
    }
    
    Format-Volume -DriveLetter $NewDriveLetter `
                    -FileSystem $FileSystem `
                    -NewFileSystemLabel $VolumeLabel `
                    -AllocationUnitSize ([int]$AllocationUnitSizeKB*1024) `
                    -Force `
                    -Confirm:$false | Out-Null
    
    Return $true
}
function Get-VolumeRemovalConfirm {

    # Return true if volume is not used by SQL Server or if user decided to go on with volume removal
    # Return false if user aborts activity or if volume is hosting live databases

    param (
        [Parameter(Mandatory=$true)]
        [string]$DriveLetter
    )

    $usedBy = Get-SqlServerVolumeUsage -DriveLetter $DriveLetter

    if($usedBy) {
    
        $backup = @()
        $data = @()
        $log = @()
        $existingDB = @()

        for($idx=0;$idx -le $usedBy.GetUpperBound(0);$idx++) {
            switch -Wildcard ($usedBy[$idx]) {
                "*_backup" {$backup += ($usedBy[$idx]).Split('_')[0]}
                "*_data" {$data += ($usedBy[$idx]).Split('_')[0]}
                "*_log" {$log += ($usedBy[$idx]).Split('_')[0]}
                "*_db*" {$existingDB += ($usedBy[$idx]).Split('_')[0]}
            }
        }
        Write-Host "Warning: the operation you chose is trying to remove volume $($DriveLetter), which is currently used as:" -ForegroundColor Yellow
        $alsoForDB = $false
        if($existingDB) {
            Write-host "`tStorage for existing databases by instance $($log -join '; ')"
            $alsoForDB = $true
        }
        if($data) {
            Write-host "`tDefault database data file path for instance $($data -join '; ')"
        }
        if($log) {
            Write-host "`tDefault database log file path for instance $($log -join '; ')"
        }
        if($backup) {
            Write-host "`tDefault backup location for instance $($backup -join '; ')"
        }
        if($alsoForDB) {
            Write-Host "`nOperation is aborted to preserve your data." -ForegroundColor Red
            Write-Host "Use appropriate menus to move listed instances databases to an alternate location, and then try again. `n" -ForegroundColor Red
            Pause
            Return $false
        }
        Write-Host "`nRemove a volume defined in SQL Server configuration paramters may lead to unwanted behaviour." -ForegroundColor Yellow
        Write-Host "Use appropriate menu to alter reported instances configuration parameters when done.`n" -ForegroundColor Yellow
        Write-Host "Other data may also be contained on this disk, proceed at your own risk.`n" -ForegroundColor Yellow
        Write-Host "PAY ATTENTION! This operation may destroy your data!" -ForegroundColor Red
        $action = Get-YN -Question "Do you want to continue?" `
                            -YesText "Remove volume with possible data lost" `
                            -NoText "Go back to previous menu" `
                            -Default 'N'
        if($action) {
            Return $true
        }
        Return $false
    }
    Return $true
}

function Get-SqlServerVersion {

    param (
        [Parameter(Mandatory=$true)]
        [string]$SqlInstanceName
    )

    $SqlServerVersion = Invoke-Sqlcmd -ServerInstance (Convert-SqlServerInstanceName -SqlInstanceName $SqlInstanceName) `
                            -Query "select SERVERPROPERTY('ProductVersion') as SqlServerVersion;" `
                            -QueryTimeout 3
    
    $SqlServerVersion.SqlServerVersion.ToString()
}
function Set-SqlInstanceOptimization {
    
    param (
        [Parameter(Mandatory=$true)]
        [string]$SqlInstanceName,
        [switch]$EnableIFI = $false,
        [switch]$EnableLockPagesInMemory = $false,
        [string[]]$TraceFlag,
        [int]$MaxServerMemoryMB
    )

    if($enableIFI) {
        Add-SQLServiceSIDtoLocalPrivilege -SqlInstanceName $SqlInstanceName -privilege "SeManageVolumePrivilege"
    }

    if($enableLockPages) {
        Add-SQLServiceSIDtoLocalPrivilege -SqlInstanceName $SqlInstanceName -privilege "SeLockMemoryPrivilege"
    }

    if($TraceFlag) {
        Add-SqlStartupParameter -SqlInstanceName $SqlInstanceName -value $traceFlag
    }

    if($MaxServerMemoryMB) {
        Set-SqlMaxServerMemory -SqlInstanceName $SqlInstanceName -MaxServerMemoryMB $MaxServerMemoryMB
    }
}

function Get-SqlServiceSIDName {

	param (
        [Parameter(Mandatory=$true)]
        [string]$SqlInstanceName
	)

	if($SqlInstanceName -eq 'MSSQLSERVER') {
            Return "NT SERVICE\MSSQLSERVER"
        }
        else {
            Return "NT SERVICE\MSSQL`$$($SqlInstanceName)"
        }
}

function Add-SqlServiceSIDtoLocalPrivilege {

    param (
        [Parameter(Mandatory=$true)]
        [string]$SqlInstanceName,
        [Parameter(Mandatory=$true)]
        [string]$privilege
    )

    $serviceSid = Get-SqlServiceSIDName -SqlInstanceName $SqlInstanceName

    #Generating a temporary file to hold new configuration
    $fileName = "$([guid]::NewGuid().ToString().SubString(0,8)).inf"
    $configFile = New-Item -Path (Join-Path -Path $env:TEMP -ChildPath $fileName) -ItemType File

    $fileHeader = @"
[Unicode]`r`n
Unicode=yes`r`n
[Version]`r`n
signature="`$CHICAGO`$"`r`n
Revision=1`r`n
[Privilege Rights]`r`n
"@

    $fileHeader | Out-File $configFile -Encoding unicode -Force

    #Generating a temporary file to hold secedit export
    $fileName = "$([guid]::NewGuid().ToString().SubString(0,8)).inf"
    $tempFile = New-Item -Path (Join-Path -Path $env:TEMP -ChildPath $fileName) -ItemType File

    #Export current local policy (user right assignment area)
    secedit /export /areas USER_RIGHTS /cfg $tempFile

    #Looking for privilege in exported file and write config file
    $tempFileContent = Get-Content $tempFile -Encoding Unicode

    $found = $false
    for($idx=0;$idx -lt $tempFileContent.GetUpperBound(0);$idx++) {
        if($tempFileContent[$idx].StartsWith($privilege)) {
            "$($tempFileContent[$idx]),$($serviceSid)" | Out-File $configFile -Append -Encoding unicode -Force
            $found = $true
        }
    }
    if(-not $found) {
        "$($privilege) = $($serviceSid)" | Out-File $configFile -Append -Encoding unicode -Force
    }

    #Import config
    secedit /configure /db secedit.sdb /cfg $configFile | Out-Null

    #Removing temp file
    $tempFile | Remove-Item -force
    $configFile | Remove-Item -force

}
function Add-SqlStartupParameter {
    
    param (
        [Parameter(Mandatory=$true)]
        [string]$SqlInstanceName,
        [Parameter(Mandatory=$true)]
        [string[]]$value
    )

    $Parameters = @()

    $sqlSvc = Get-SQLService -SqlInstanceName $SqlInstanceName
    [string[]]$currParameters = ($sqlSvc.StartupParameters).Split(';')
    $value | ForEach-Object { if($_ -notin $currParameters) { $Parameters += $_} }
        
    if($Parameters) {
        $Parameters | ForEach-Object { $currParameters += $_ }
    }
    $newParameters = $currParameters -join ';'

    $sqlSvc.StartupParameters = $newParameters
    $sqlSvc.Alter()
    $sqlSvc.Refresh()

    #Restart SQL Server
    Restart-SqlService -SqlService $sqlSvc
}

function Set-SqlMaxServerMemory {
    
    param (
        [Parameter(Mandatory=$true)]
        [string]$SqlInstanceName,

        [Parameter(Mandatory=$true)]
        [int]$MaxServerMemoryMB
    )

    $srv = Get-SQLServer -SqlInstanceName $SqlInstanceName

    $srv.Configuration.MaxServerMemory.ConfigValue = $MaxServerMemoryMB
    $srv.Alter()
    $srv.Refresh()

}

function Get-SQLServer {

    param (
        [Parameter(Mandatory=$false)]
        [String]$SqlInstanceName='MSSQLSERVER'
    )

    [reflection.assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo') | Out-Null

    $connStr = Convert-SqlServerInstanceName -SqlInstanceName $SqlInstanceName

    Return (new-object Microsoft.SqlServer.Management.Smo.Server $connStr)

}

function Convert-SqlServerInstanceName {

    param (
        [Parameter(Mandatory=$false)]
        [String]$SqlInstanceName='MSSQLSERVER'
    )

    $InstanceName = $env:COMPUTERNAME
    if($SqlInstanceName -ne 'MSSQLSERVER') {
        if($SqlInstanceName.IndexOf('$') -ne -1) {
            $InstanceName = "$env:COMPUTERNAME\$($SqlInstanceName.Split('$')[1])"
        } 
        $InstanceName = "$env:COMPUTERNAME\$SqlInstanceName"
    }
    $InstanceName

}

function Restart-SqlService {

    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.SqlServer.Management.Smo.Wmi.Service]$SqlService
    )

    Write-Verbose -Message "Restarting '$($SqlService.name)' ..."
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.WmiEnum") | Out-Null
    Stop-SqlService -SqlService $sqlService
    Start-SqlService -SqlService $sqlService
}

function Set-SQLServerDefaultPath {

    param(
        [Parameter(Mandatory=$true)]
        [string]$SqlInstanceName,
        [string]$DataPath,
        [string]$LogPath,
        [string]$BackupPath
    )

    $srv = Get-SQLServer -SqlInstanceName $SqlInstanceName
    $changed = $false

    if($DataPath) {
        $srv.DefaultFile = $dataPath
        $changed = $true
    }
    if($logPath) {
        $srv.DefaultLog = $logPath
        $changed = $true
    }
    if($BackupPath) {
        $srv.BackupDirectory = $BackupPath
        $changed = $true
    }

    if($changed) {

        $srv.Alter()
        Restart-SqlService -SqlService (Get-SQLService -SqlInstanceName $SqlInstanceName)
    }
    
}
function Move-SystemDatabaseAndTrace {
    param (
        [Parameter(Mandatory=$true)]
        [string] $SqlInstanceName,
        [Parameter(Mandatory=$true)]
        [string] $DataPath,
        [string] $LogPath = $DataPath,
        [string] $TempDBDataPath = $DataPath,
        [string] $TempDBLogPath = $LogPath,
        [string] $ErrorLogPath
    )

    #Prepare file move statemets
    $getDBpathQry = @"
        select	db.name,
                mf.physical_name,
                case mf.type when 0 then '{0}' else '{1}' end +
                RIGHT(mf.physical_name, CHARINDEX('\', REVERSE(mf.physical_name))) as DestPath
        from	sys.databases db inner join sys.master_files mf
        on		db.database_id = mf.database_id
        where	db.database_id <= 4
        Order by db.database_id
"@

    #$dbFileList = Get-DynSqlOutput -DynSqlStmt $getDBpathQry -SqlInstanceName $SqlInstanceName
    $dbFileList = Invoke-SQLCmd -ServerInstance (Convert-SqlServerInstanceName -SqlInstanceName $SqlInstanceName) -Query $getDBpathQry

    $moveStmt = @()
    foreach($dbFile in $dbFileList) {
        $moveStmt += "Move-Item -path '$($dbFile.physical_name)' -destination '$($dbFile.DestPath)' -force" -f $dataPath, $logPath, $tempDBDataPath, $tempDBLogPath
    } 

    #Alter Database move file
    $alterDBQry = @"
        select	'ALTER DATABASE [' + db.name + '] MODIFY FILE ' +
                '(NAME = N''' + mf.name +''', ' +
                'FILENAME = ''' + 
                case 
                    when (db.name = 'tempdb' and mf.type = 0) then '{2}'
                    when (db.name = 'tempdb' and mf.type = 1) then '{3}'
                    when (db.name <> 'tempdb' and mf.type = 0) then '{0}'
                    when (db.name <> 'tempdb' and mf.type = 1) then '{1}'
                    else '{0}'
                end +
                RIGHT(mf.physical_name, CHARINDEX('\', REVERSE(mf.physical_name)))  + ''');'
        from	sys.databases db inner join sys.master_files mf
        on		db.database_id = mf.database_id
        where	db.database_id <= 4
                and db.name <> 'master'
        Order by db.database_id
"@

    $qry = $alterDBQry -f $DataPath, $LogPath, $TempDBDataPath, $TempDBLogPath

    Invoke-DynSqlQry -DynSqlStmt $qry -SqlInstanceName $SqlInstanceName

    #Stop SQL Server
    $sqlSvc = Get-SQLService -SqlInstanceName $SqlInstanceName
    Stop-SqlService -SqlService $sqlSvc

    #Phisically move db files
    $moveStmt | ForEach-Object {Invoke-Expression $_}

    #Alter Startup Parameters for master and errorlog
    [string[]]$currParameters = ($sqlSvc.StartupParameters).Split(';')
    for($idx=0;$idx -le $currParameters.GetUpperBound(0);$idx++) {
        Switch -Wildcard ($currParameters[$idx]) {
            "-d*" {$currParameters[$idx] = "-d$($dataPath)\master.mdf"}
            "-l*" {$currParameters[$idx] = "-l$($logPath)\mastlog.ldf"}
            "-e*" {$currParameters[$idx] = "-e$($errorLogPath)\ERRORLOG"}
        }
    }
    $newParameters = $currParameters -join ';'
    $sqlSvc.StartupParameters = $newParameters
    $sqlSvc.Alter()
    $sqlSvc.Refresh()
    
    #Start SQL Server
    Start-SqlService -SqlService $sqlSvc
}

function Invoke-DynSqlQry {

    param (
        [Parameter(Mandatory=$true)]
        [string]$DynSqlStmt,
        [Parameter(Mandatory=$true)]
        [string]$SqlInstanceName
    )

    $InstanceName = Convert-SqlServerInstanceName -SqlInstanceName $SqlInstanceName
    $DynSqlOut = Invoke-SQLCmd -ServerInstance $InstanceName -Query $DynSqlStmt
    $DynSqlOut | ForEach-Object {Invoke-SqlCmd -ServerInstance $InstanceName -query $_.Column1}
}

function Start-SqlService {
    
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.SqlServer.Management.Smo.Wmi.Service]$SqlService, 
        [Microsoft.SqlServer.Management.Smo.Wmi.ServiceStartMode]$StartupType
    )

    if($StartupType) {
        $SqlService.StartMode = $StartupType
        $sqlService.Alter()
    }

    Write-Verbose -Message "Starting '$($sqlService.name)' ..."
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.WmiEnum") | Out-Null
    if ($SqlService.ServiceState -eq [Microsoft.SqlServer.Management.Smo.Wmi.ServiceState]::Stopped)
    {
        Start-Service -Name $SqlService.Name
        $SqlService.Refresh()
        while ($SqlService.ServiceState -ne [Microsoft.SqlServer.Management.Smo.Wmi.ServiceState]::Running)
        {
            $SqlService.Refresh()
        }
    }
}

function Stop-SqlService {

    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.SqlServer.Management.Smo.Wmi.Service]$SqlService, 
        [Microsoft.SqlServer.Management.Smo.Wmi.ServiceStartMode]$StartupType
    )

    if($StartupType) {
        $SqlService.StartMode = $StartupType
        $sqlService.Alter()
    }

    Write-Verbose -Message "Stopping '$($SqlService.name)' ..."
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.WmiEnum") | Out-Null
    Stop-Service -Name $SqlService.Name -Force
    $SqlService.Refresh()
    while ($SqlService.ServiceState -ne [Microsoft.SqlServer.Management.Smo.Wmi.ServiceState]::Stopped)
    {
        $SqlService.Refresh()
    }
}

function Get-SQLService {

    # Return a single Microsoft.SqlServer.Management.Smo.Wmi.Service object related
    # to SqlInstanceName or ServiceName parameters, or a collection of Services if
    # -All parameter is present

    param (
        [Parameter(Mandatory=$False)]
        [String]$SqlInstanceName='MSSQLSERVER',

        [Parameter(Mandatory=$False)]
        [String]$ServiceName,

        [Parameter(Mandatory=$False)]
        [Switch]$All
    )
    
    [reflection.assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement') | Out-Null

    $mc = new-object Microsoft.SQLServer.Management.SMO.WMI.ManagedComputer localhost

    if($All) {
        Return [Microsoft.SqlServer.Management.Smo.Wmi.ServiceCollection]$mc.Services
    }
    elseif ($ServiceName) {
        Return [Microsoft.SqlServer.Management.Smo.Wmi.Service]$mc.Services[$ServiceName]
    }
    else {
        if($SqlInstanceName -ne 'MSSQLSERVER') {
            Return [Microsoft.SqlServer.Management.Smo.Wmi.Service]$mc.Services["MSSQL`$$SqlInstanceName"]
        }
        else {
            Return [Microsoft.SqlServer.Management.Smo.Wmi.Service]$mc.Services[$SqlInstanceName]
        }
    }

}

Export-ModuleMember -Function @("New-StoragePoolForSql", "New-SqlDirectory", "New-SingleDiskForSql", "Set-SqlInstanceOptimization", "Set-SQLServerDefaultPath", "Move-SystemDatabaseAndTrace", "Get-SqlServerVersion", "Get-PhysicalDiskExt")