configuration SqlDscConfig
{
    param
    (
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [String]$DomainNetbiosName=(Get-NetBIOSName -DomainName $DomainName),

        [Bool]$prepareForFCI=$false,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    )

    Import-DscResource -ModuleName xComputerManagement, xActiveDirectory, PSDesiredStateConfiguration, SqlServerDsc, PackageManagement
    [System.Management.Automation.PSCredential]$SqlAdministratorCredential = New-Object System.Management.Automation.PSCredential ("$env:COMPUTERNAME\$($Admincreds.UserName)", $Admincreds.Password)

    if ($DomainName)
    {
        [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
    }

    Node localhost
    {
        PackageManagementSource PSGallery
        {
            Ensure      = "Present"
            Name        = "PSGallery"
            ProviderName= "PowerShellGet"
            SourceLocation   = "https://www.powershellgallery.com/api/v2"
            InstallationPolicy ="Trusted"
        }

        PackageManagement PSModuleDbaTools
        {
            Ensure               = "Present"
            Name                 = "DbaTools"
            Source               = "PSGallery"
            DependsOn            = "[PackageManagementSource]PSGallery"
        }
    

        if ($prepareForFCI) {

            script 'CustomScript'
            {
                PsDscRunAsCredential = $SqlAdministratorCredential
                GetScript       = { return @{result = 'result'} }
                TestScript      = { return $false }
                SetScript       = {
                    
                    $logFile = "C:\SqlConfig.log"

                    # Remove default instance
                    Set-Location -Path "C:\SQLServerFull"
                    .\Setup.exe /Action=Uninstall /FEATURES=SQL /INSTANCENAME=MSSQLSERVER /Q |
                        Out-File -FilePath $LogFile -Append
                }
            }

        } else {

            script 'CustomScript'
            {
                DependsOn       = "[PackageManagement]PSModuleDbaTools"
                PsDscRunAsCredential = $SqlAdministratorCredential
                GetScript       =  { return @{result = 'result'} }
                TestScript      = { return $false }
                SetScript       = {
                    
                    $logFile = "C:\SqlConfig.log"

                    # Setting MaxDOP to recommended value
                    Test-DbaMaxDop -SqlInstance $ENV:COMPUTERNAME |
                        Set-DbaMaxDop |
                        Out-File -FilePath $LogFile -Append
                    
                    # Setting MaxServerMemory to recommended value
                    Test-DbaMaxMemory -SqlInstance $ENV:COMPUTERNAME -Verbose |
                        Set-DbaMaxMemory -Verbose |
                        Out-File -FilePath $LogFile -Append

                    # Enabling IFI and lock pages in memory
                    Set-DbaPrivilege -ComputerName $ENV:COMPUTERNAME `
                        -Type IFI,LPIM `
                        -Verbose |
                        Out-File -FilePath $LogFile -Append
                }
            }

        }

        if ($DomainName)
        {
            WindowsFeature ADPS
            {
                Name = "RSAT-AD-PowerShell"
                Ensure = "Present"
                DependsOn = "[Script]CustomScript"
            }

            xWaitForADDomain DscForestWait 
            { 
                DomainName = $DomainName 
                DomainUserCredential= $DomainCreds
                RetryCount = $RetryCount 
                RetryIntervalSec = $RetryIntervalSec 
                DependsOn = "[WindowsFeature]ADPS"
            }
            
            xComputer DomainJoin
            {
                Name = $env:COMPUTERNAME
                DomainName = $DomainName
                Credential = $DomainCreds
                DependsOn = "[xWaitForADDomain]DscForestWait"
            }

            if (-not $prepareForFCI) {
                
                SqlServerLogin Add_WindowsUser
                {
                    Ensure               = 'Present'
                    Name                 = "$DomainNetbiosName\$($AdminCreds.UserName)"
                    LoginType            = 'WindowsUser'
                    ServerName           = $env:COMPUTERNAME
                    InstanceName         = 'MSSQLSERVER'
                    PsDscRunAsCredential = $SqlAdministratorCredential
                    DependsOn = "[xComputer]DomainJoin"
                }

                SqlServerRole Add_ServerRole_SysAdmin
                {
                    Ensure               = 'Present'
                    ServerRoleName       = 'sysadmin'
                    MembersToInclude     = "$DomainNetbiosName\$($AdminCreds.UserName)"
                    ServerName           = $env:COMPUTERNAME
                    InstanceName         = 'MSSQLSERVER'
                    PsDscRunAsCredential = $SqlAdministratorCredential
                    DependsOn = "[SqlServerLogin]Add_WindowsUser"
                }
            }
        }

        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
        }

    }
}
function Get-NetBIOSName
{ 
    [OutputType([string])]
    param(
        [string]$DomainName
    )

    if ($DomainName.Contains('.')) {
        $length=$DomainName.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainName.Substring(0,$length)
    }
    else {
        if ($DomainName.Length -gt 15) {
            return $DomainName.Substring(0,15)
        }
        else {
            return $DomainName
        }
    }
}
