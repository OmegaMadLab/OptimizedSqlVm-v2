param(
    [string]$WorkingPath,
    [string]$DataPath,
    [string]$LogPath,
    [string]$BackupPath,
    [string]$ErrorLogPath,
    [string]$WorkloadType
)

Import-Module "$WorkingPath\Optimize-SqlIaasVm-CSE.psm1"

$SqlInstanceName = "MSSQLSERVER"

try {
    Set-SQLServerDefaultPath -SqlInstanceName $SqlInstanceName `
        -DataPath $DataPath `
        -LogPath $LogPath `
        -BackupPath $BackupPath

    Write-Output "New data path:`t$DataPath"
    Write-Output "New log path:`t$LogPath"
    Write-Output "New backup path:`t$BackupPath"
}
catch {
    Write-Output "Error while changing SQL Server default paths"
    Throw $_
}

try {
    Move-SystemDatabaseAndTrace -SqlInstanceName $SqlInstanceName `
        -DataPath $DataPath `
        -LogPath $LogPath `
        -ErrorLogPath $ErrorLogPath

    Write-Output "System DBs moved to new default paths"
    Write-Output "New ErrorLog path:`t$ErrorLogPath"
}
catch {
    Write-Output "Error while changing moving system databases and errorlog:"
    Throw $_
}

try {
    #Defining MaxServerMemory value depending on installed memory
    $InstalledMemory = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory/1MB)

    Switch($InstalledMemory) {
        {$_ -le 4096} { $MaxServerMemory = $InstalledMemory - 2048 }
        {$_ -gt 4096 -and $_ -le 8192} { $MaxServerMemory = $InstalledMemory - 3072 }
        {$_ -gt 8192} { $MaxServerMemory = $InstalledMemory - 4096 }
        default { $MaxServerMemory = 2147483647}
    }

    Switch ($WorkloadType) {
        "OLTP" {$traceFlag = @("-T1117", "-T1118")}
        "DW" {$traceFlag = @("-T1117", "-T610")}
    }

    $SqlServerVersion = Get-SqlServerVersion -SqlInstanceName $SqlInstanceName

    if([int]($SqlServerVersion.split(".")[0]) -lt 13) {
        Set-SQLInstanceOptimization -SqlInstanceName $SqlInstanceName `
            -EnableIFI `
            -EnableLockPagesInMemory `
            -TraceFlag $traceFlag `
            -MaxServerMemoryMB $MaxServerMemory
    } else {
        Set-SQLInstanceOptimization -SqlInstanceName $SqlInstanceName `
            -EnableIFI `
            -EnableLockPagesInMemory `
            -MaxServerMemoryMB $MaxServerMemory
    }

    Write-Output "Instant File Initialization enabled for current service SID"
    Write-Output "Locked pages enabled for current service SID"
    Write-Output "Max Server Memory limited to $MaxServerMemory MB"
    if([int]($SqlServerVersion.split(".")[0]) -lt 13) {
        Write-Output "Trace flag $($traceFlag -join ",") enabled"
    }
}
catch {
    Write-Output "Error while applying SQL Server optimizations:"
    Throw $_
}