# To run these tests, we have to fake login credentials
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
param ()

# Unit Test Template Version: 1.1.0

$script:moduleName = 'SqlServerDscHelper'

[System.String] $script:moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ( (-not (Test-Path -Path (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests'))) -or `
    (-not (Test-Path -Path (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1'))) )
{
    & git @('clone','https://github.com/PowerShell/DscResource.Tests.git',(Join-Path -Path $script:moduleRoot -ChildPath '\DSCResource.Tests\'))
}

Import-Module (Join-Path -Path $script:moduleRoot -ChildPath 'DSCResource.Tests\TestHelper.psm1') -Force
Import-Module (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent) -ChildPath 'SqlServerDscHelper.psm1') -Scope Global -Force

# Loading mocked classes
Add-Type -Path ( Join-Path -Path ( Join-Path -Path $PSScriptRoot -ChildPath Stubs ) -ChildPath SMO.cs )

# Begin Testing
InModuleScope $script:moduleName {
    $mockNewObject_MicrosoftAnalysisServicesServer = {
        return New-Object -TypeName Object |
                    Add-Member -MemberType ScriptMethod -Name Connect -Value {
                        param(
                            [Parameter(Mandatory = $true)]
                            [ValidateNotNullOrEmpty()]
                            [System.String]
                            $dataSource
                        )

                        if ($dataSource -ne $mockExpectedDataSource)
                        {
                            throw ("Datasource was expected to be '{0}', but was '{1}'." -f $mockExpectedDataSource,$dataSource)
                        }

                        if ($mockThrowInvalidOperation)
                        {
                            throw 'Unable to connect.'
                        }
                    } -PassThru -Force
    }

    $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter = {
        $TypeName -eq 'Microsoft.AnalysisServices.Server'
    }

    $mockNewObject_MicrosoftDatabaseEngine = {
        <#
            $ArgumentList[0] will contain the ServiceInstance when calling mock New-Object.
            But since the mock New-Object will also be called without arguments, we first
            have to evaluate if $ArgumentList contains values.
        #>
        if( $ArgumentList.Count -gt 0)
        {
            $serverInstance = $ArgumentList[0]
        }

        return New-Object -TypeName Object |
            Add-Member -MemberType ScriptProperty -Name Status -Value {
                if ($mockExpectedDatabaseEngineInstance -eq 'MSSQLSERVER')
                {
                    $mockExpectedServiceInstance = $mockExpectedDatabaseEngineServer
                }
                else
                {
                    $mockExpectedServiceInstance = "$mockExpectedDatabaseEngineServer\$mockExpectedDatabaseEngineInstance"
                }

                if ( $this.ConnectionContext.ServerInstance -eq $mockExpectedServiceInstance )
                {
                    return 'Online'
                }
                else
                {
                    return $null
                }
            } -PassThru |
            Add-Member -MemberType NoteProperty -Name ConnectionContext -Value (
                New-Object -TypeName Object |
                    Add-Member -MemberType NoteProperty -Name ServerInstance -Value $serverInstance -PassThru |
                    Add-Member -MemberType NoteProperty -Name ConnectAsUser -Value $false -PassThru |
                    Add-Member -MemberType NoteProperty -Name ConnectAsUserPassword -Value '' -PassThru |
                    Add-Member -MemberType NoteProperty -Name ConnectAsUserName -Value '' -PassThru |
                    Add-Member -MemberType ScriptMethod -Name Connect -Value {
                        if ($mockExpectedDatabaseEngineInstance -eq 'MSSQLSERVER')
                        {
                            $mockExpectedServiceInstance = $mockExpectedDatabaseEngineServer
                        }
                        else
                        {
                            $mockExpectedServiceInstance = "$mockExpectedDatabaseEngineServer\$mockExpectedDatabaseEngineInstance"
                        }

                        if ($this.serverInstance -ne $mockExpectedServiceInstance)
                        {
                            throw ("Mock method Connect() was expecting ServerInstance to be '{0}', but was '{1}'." -f $mockExpectedServiceInstance, $this.serverInstance )
                        }

                        if ($mockThrowInvalidOperation)
                        {
                            throw 'Unable to connect.'
                        }
                    } -PassThru -Force
            ) -PassThru -Force
    }

    $mockNewObject_MicrosoftDatabaseEngine_ParameterFilter = {
        $TypeName -eq 'Microsoft.SqlServer.Management.Smo.Server'
    }

    $mockThrowLocalizedMessage = {
        throw $Message
    }

    $mockSqlMajorVersion = 13
    $mockInstanceName = 'TEST'

    $mockSetupCredentialUserName = 'TestUserName12345'
    $mockSetupCredentialPassword = 'StrongOne7.'
    $mockSetupCredentialSecurePassword = ConvertTo-SecureString -String $mockSetupCredentialPassword -AsPlainText -Force
    $mockSetupCredential = New-Object -TypeName PSCredential -ArgumentList ($mockSetupCredentialUserName, $mockSetupCredentialSecurePassword)

    Describe 'Testing Restart-SqlService' {
        Context 'Restart-SqlService standalone instance' {
            BeforeEach {
                Mock -CommandName Connect-SQL -MockWith {
                    return @{
                        Name = 'MSSQLSERVER'
                        InstanceName = ''
                        ServiceName = 'MSSQLSERVER'
                        Status = $mockDynamicStatus
                    }
                } -Verifiable -ParameterFilter { $SQLInstanceName -eq 'MSSQLSERVER' }

                Mock -CommandName Connect-SQL -MockWith {
                    return @{
                        Name = 'NOAGENT'
                        InstanceName = 'NOAGENT'
                        ServiceName = 'NOAGENT'
                        Status = $mockDynamicStatus
                    }
                } -Verifiable -ParameterFilter { $SQLInstanceName -eq 'NOAGENT' }

                Mock -CommandName Connect-SQL -MockWith {
                    return @{
                        Name = 'STOPPEDAGENT'
                        InstanceName = 'STOPPEDAGENT'
                        ServiceName = 'STOPPEDAGENT'
                        Status = $mockDynamicStatus
                    }
                } -Verifiable -ParameterFilter { $SQLInstanceName -eq 'STOPPEDAGENT' }
            }

            BeforeAll {
                ## SQL instance with running SQL Agent Service
                Mock -CommandName Get-Service -MockWith {
                    return @{
                        Name = 'MSSQLSERVER'
                        DisplayName = 'Microsoft SQL Server (MSSQLSERVER)'
                        DependentServices = @(
                            @{
                                Name = 'SQLSERVERAGENT'
                                DisplayName = 'SQL Server Agent (MSSQLSERVER)'
                                Status = 'Running'
                                DependentServices = @()
                            }
                        )
                    }
                } -Verifiable -ParameterFilter { $DisplayName -eq 'SQL Server (MSSQLSERVER)' }

                ## SQL instance with no installed SQL Agent Service
                Mock -CommandName Get-Service -MockWith {
                    return @{
                        Name = 'MSSQL$NOAGENT'
                        DisplayName = 'Microsoft SQL Server (NOAGENT)'
                        DependentServices = @()
                    }
                } -Verifiable -ParameterFilter { $DisplayName -eq 'SQL Server (NOAGENT)' }

                ## SQL instance with stopped SQL Agent Service
                Mock -CommandName Get-Service -MockWith {
                    return @{
                        Name = 'MSSQL$STOPPEDAGENT'
                        DisplayName = 'Microsoft SQL Server (STOPPEDAGENT)'
                        DependentServices = @(
                            @{
                                Name = 'SQLAGENT$STOPPEDAGENT'
                                DisplayName = 'SQL Server Agent (STOPPEDAGENT)'
                                Status = 'Stopped'
                                DependentServices = @()
                            }
                        )
                    }
                } -Verifiable -ParameterFilter { $DisplayName -eq 'SQL Server (STOPPEDAGENT)' }

                Mock -CommandName Restart-Service -Verifiable
                Mock -CommandName Start-Service -Verifiable
            }

            $mockDynamicStatus = 'Online'

            It 'Should restart SQL Service and running SQL Agent service' {
                { Restart-SqlService -SQLServer $env:ComputerName -SQLInstanceName 'MSSQLSERVER' } | Should -Not -Throw

                Assert-MockCalled -CommandName Connect-SQL -ParameterFilter {
                    $PSBoundParameters.ContainsKey('ErrorAction') -eq $false
                } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-Service -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Restart-Service -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Start-Service -Scope It -Exactly -Times 1
            }

            It 'Should restart SQL Service and not try to restart missing SQL Agent service' {
                { Restart-SqlService -SQLServer $env:ComputerName -SQLInstanceName 'NOAGENT' } | Should -Not -Throw

                Assert-MockCalled -CommandName Connect-SQL {
                    $PSBoundParameters.ContainsKey('ErrorAction') -eq $false
                } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-Service -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Restart-Service -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Start-Service -Scope It -Exactly -Times 0
            }

            It 'Should restart SQL Service and not try to restart stopped SQL Agent service' {
                { Restart-SqlService -SQLServer $env:ComputerName -SQLInstanceName 'STOPPEDAGENT' } | Should -Not -Throw

                Assert-MockCalled -CommandName Connect-SQL {
                    $PSBoundParameters.ContainsKey('ErrorAction') -eq $false
                } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-Service -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Restart-Service -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Start-Service -Scope It -Exactly -Times 0
            }

            Context 'When it fails to connect to the instance within the timeout period' {
                BeforeEach {
                    Mock -CommandName Connect-SQL -MockWith {
                        return @{
                            Name = 'MSSQLSERVER'
                            InstanceName = ''
                            ServiceName = 'MSSQLSERVER'
                            Status = $mockDynamicStatus
                        }
                    } -Verifiable -ParameterFilter { $SQLInstanceName -eq 'MSSQLSERVER' }
                }

                $mockDynamicStatus = 'Offline'

                It 'Should throw the correct error message' {
                    $errorMessage = $localizedData.FailedToConnectToInstanceTimeout -f $env:ComputerName, 'MSSQLSERVER', 1

                    {
                        Restart-SqlService -SQLServer $env:ComputerName -SQLInstanceName 'MSSQLSERVER' -Timeout 1
                    } | Should -Throw $errorMessage

                    Assert-MockCalled -CommandName Connect-SQL -ParameterFilter {
                        $PSBoundParameters.ContainsKey('ErrorAction') -eq $false
                    } -Scope It -Exactly -Times 1

                    Assert-MockCalled -CommandName Connect-SQL -ParameterFilter {
                        $PSBoundParameters.ContainsKey('ErrorAction') -eq $true
                    } -Scope It -Exactly -Times 1
                }
            }
        }

        Context 'Restart-SqlService clustered instance' {
            BeforeEach {
                Mock -CommandName Connect-SQL -MockWith {
                    return @{
                        Name = 'MSSQLSERVER'
                        InstanceName = ''
                        ServiceName = 'MSSQLSERVER'
                        IsClustered = $true
                        Status = $mockDynamicStatus
                    }
                } -Verifiable -ParameterFilter { ($SQLServer -eq 'CLU01') -and ($SQLInstanceName -eq 'MSSQLSERVER') }

                Mock -CommandName Connect-SQL -MockWith {
                    return @{
                        Name = 'NAMEDINSTANCE'
                        InstanceName = 'NAMEDINSTANCE'
                        ServiceName = 'NAMEDINSTANCE'
                        IsClustered = $true
                        Status = $mockDynamicStatus
                    }
                } -Verifiable -ParameterFilter { ($SQLServer -eq 'CLU01') -and ($SQLInstanceName -eq 'NAMEDINSTANCE') }

                Mock -CommandName Connect-SQL -MockWith {
                    return @{
                        Name = 'STOPPEDAGENT'
                        InstanceName = 'STOPPEDAGENT'
                        ServiceName = 'STOPPEDAGENT'
                        IsClustered = $true
                        Status = $mockDynamicStatus
                    }
                } -Verifiable -ParameterFilter { ($SQLServer -eq 'CLU01') -and ($SQLInstanceName -eq 'STOPPEDAGENT') }
            }

            BeforeAll {
                Mock -CommandName Get-CimInstance -MockWith {
                    @('MSSQLSERVER','NAMEDINSTANCE','STOPPEDAGENT') | ForEach-Object {
                        $mock = New-Object -TypeName Microsoft.Management.Infrastructure.CimInstance -ArgumentList 'MSCluster_Resource','root/MSCluster'

                        $mock | Add-Member -MemberType NoteProperty -Name 'Name' -Value "SQL Server ($($_))" -TypeName 'String'
                        $mock | Add-Member -MemberType NoteProperty -Name 'Type' -Value 'SQL Server' -TypeName 'String'
                        $mock | Add-Member -MemberType NoteProperty -Name 'PrivateProperties' -Value @{ InstanceName = $_ }

                        return $mock
                    }
                } -Verifiable -ParameterFilter { ($ClassName -eq 'MSCluster_Resource') -and ($Filter -eq "Type = 'SQL Server'") }

                Mock -CommandName Get-CimAssociatedInstance -MockWith {
                    $mock = New-Object -TypeName Microsoft.Management.Infrastructure.CimInstance -ArgumentList 'MSCluster_Resource','root/MSCluster'

                    $mock | Add-Member -MemberType NoteProperty -Name 'Name' -Value "SQL Server Agent ($($InputObject.PrivateProperties.InstanceName))" -TypeName 'String'
                    $mock | Add-Member -MemberType NoteProperty -Name 'Type' -Value 'SQL Server Agent' -TypeName 'String'
                    $mock | Add-Member -MemberType NoteProperty -Name 'State' -Value (@{ $true = 3; $false = 2 }[($InputObject.PrivateProperties.InstanceName -eq 'STOPPEDAGENT')]) -TypeName 'Int32'

                    return $mock
                } -Verifiable -ParameterFilter { $ResultClassName -eq 'MSCluster_Resource' }

                Mock -CommandName Invoke-CimMethod -ParameterFilter { $MethodName -eq 'TakeOffline' } -Verifiable
                Mock -CommandName Invoke-CimMethod -ParameterFilter { $MethodName -eq 'BringOnline' } -Verifiable
            }

            $mockDynamicStatus = 'Online'

            It 'Should restart SQL Server and SQL Agent resources for a clustered default instance' {
                { Restart-SqlService -SQLServer 'CLU01' } | Should -Not -Throw

                Assert-MockCalled -CommandName Connect-SQL {
                    $PSBoundParameters.ContainsKey('ErrorAction') -eq $false
                } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-CimInstance -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-CimAssociatedInstance -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Invoke-CimMethod -ParameterFilter { $MethodName -eq 'TakeOffline' } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Invoke-CimMethod -ParameterFilter { $MethodName -eq 'BringOnline' } -Scope It -Exactly -Times 2
            }

            It 'Should restart SQL Server and SQL Agent resources for a clustered named instance' {
                { Restart-SqlService -SQLServer 'CLU01' -SQLInstanceName 'NAMEDINSTANCE' } | Should -Not -Throw

                Assert-MockCalled -CommandName Connect-SQL {
                    $PSBoundParameters.ContainsKey('ErrorAction') -eq $false
                } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-CimInstance -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-CimAssociatedInstance -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Invoke-CimMethod -ParameterFilter { $MethodName -eq 'TakeOffline' } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Invoke-CimMethod -ParameterFilter { $MethodName -eq 'BringOnline' } -Scope It -Exactly -Times 2
            }

            It 'Should not try to restart a SQL Agent resource that is not online' {
                { Restart-SqlService -SQLServer 'CLU01' -SQLInstanceName 'STOPPEDAGENT' } | Should -Not -Throw

                Assert-MockCalled -CommandName Connect-SQL {
                    $PSBoundParameters.ContainsKey('ErrorAction') -eq $false
                } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-CimInstance -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Get-CimAssociatedInstance -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Invoke-CimMethod -ParameterFilter { $MethodName -eq 'TakeOffline' } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Invoke-CimMethod -ParameterFilter { $MethodName -eq 'BringOnline' } -Scope It -Exactly -Times 1
            }
        }
    }

    Describe 'Testing Connect-SQLAnalysis' {
        BeforeEach {
            Mock -CommandName New-InvalidOperationException -MockWith $mockThrowLocalizedMessage -Verifiable
            Mock -CommandName New-Object `
                -MockWith $mockNewObject_MicrosoftAnalysisServicesServer `
                -ParameterFilter $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter `
                -Verifiable
        }

        Context 'When connecting to the default instance using Windows Authentication' {
            It 'Should not throw when connecting' {
                $mockExpectedDataSource = "Data Source=$env:COMPUTERNAME"

                { Connect-SQLAnalysis } | Should -Not -Throw

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter
            }
        }

        Context 'When connecting to the named instance using Windows Authentication' {
            It 'Should not throw when connecting' {
                $mockExpectedDataSource = "Data Source=$env:COMPUTERNAME\$mockInstanceName"

                { Connect-SQLAnalysis -SQLInstanceName $mockInstanceName } | Should -Not -Throw

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter
            }
        }

        Context 'When connecting to the named instance using Windows Authentication impersonation' {
            It 'Should not throw when connecting' {
                $mockExpectedDataSource = "Data Source=$env:COMPUTERNAME\$mockInstanceName;User ID=$mockSetupCredentialUserName;Password=$mockSetupCredentialPassword"

                { Connect-SQLAnalysis -SQLInstanceName $mockInstanceName -SetupCredential $mockSetupCredential } | Should -Not -Throw

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter
            }
        }

        Context 'When connecting to the default instance using the correct service instance but does not return a correct Analysis Service object' {
            It 'Should throw the correct error' {
                $mockExpectedDataSource = ''

                Mock -CommandName New-Object `
                    -ParameterFilter $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter `
                    -Verifiable

                $mockCorrectErrorMessage = ($script:localizedData.FailedToConnectToAnalysisServicesInstance -f $env:COMPUTERNAME)
                { Connect-SQLAnalysis } | Should -Throw $mockCorrectErrorMessage

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter
            }
        }

        Context 'When connecting to the default instance using a Analysis Service instance that does not exist' {
            It 'Should throw the correct error' {
                $mockExpectedDataSource = "Data Source=$env:COMPUTERNAME"

                # Force the mock of Connect() method to throw 'Unable to connect.'
                $mockThrowInvalidOperation = $true

                $mockCorrectErrorMessage = ($script:localizedData.FailedToConnectToAnalysisServicesInstance -f $env:COMPUTERNAME)
                { Connect-SQLAnalysis } | Should -Throw $mockCorrectErrorMessage

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter

                # Setting it back to the default so it does not disturb other tests.
                $mockThrowInvalidOperation = $false
            }
        }

        # This test is to test the mock so that it throws correct when data source is not the expected data source
        Context 'When connecting to the named instance using another data source then expected' {
            It 'Should throw the correct error' {
                $mockExpectedDataSource = "Force wrong data source"

                $testParameters = @{
                    SQLServer = 'DummyHost'
                    SQLInstanceName = $mockInstanceName
                }

                $mockCorrectErrorMessage = ($script:localizedData.FailedToConnectToAnalysisServicesInstance -f "$($testParameters.SQLServer)\$($testParameters.SQLInstanceName)")
                { Connect-SQLAnalysis @testParameters } | Should -Throw $mockCorrectErrorMessage

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftAnalysisServicesServer_ParameterFilter
            }
        }

        Assert-VerifiableMock
    }

    Describe 'Testing Invoke-Query' {
        $mockExpectedQuery = ''

        $mockConnectSql = {
            return @(
                (
                    New-Object -TypeName PSObject -Property @{
                        Databases = @{
                            'master' = (
                                New-Object -TypeName PSObject -Property @{ Name = 'master' } |
                                    Add-Member -MemberType ScriptMethod -Name ExecuteNonQuery -Value {
                                        param
                                        (
                                            [Parameter()]
                                            [System.String]
                                            $sqlCommand
                                        )

                                        if ( $sqlCommand -ne $mockExpectedQuery )
                                        {
                                            throw
                                        }
                                    } -PassThru |
                                    Add-Member -MemberType ScriptMethod -Name ExecuteWithResults -Value {
                                        param
                                        (
                                            [Parameter()]
                                            [System.String]
                                            $sqlCommand
                                        )

                                        if ( $sqlCommand -ne $mockExpectedQuery )
                                        {
                                            throw
                                        }

                                        return New-Object -TypeName System.Data.DataSet
                                    } -PassThru
                            )
                        }
                    }
                )
            )
        }

        BeforeEach {
            Mock -CommandName Connect-SQL -MockWith $mockConnectSql -ModuleName $script:DSCResourceName -Verifiable
            Mock -CommandName New-InvalidOperationException -MockWith $mockThrowLocalizedMessage -Verifiable
        }

        $queryParams = @{
            SQLServer = 'Server1'
            SQLInstanceName = 'MSSQLSERVER'
            Database = 'master'
            Query = ''
        }

        Context 'Execute a query with no results' {
            It 'Should execute the query silently' {
                $queryParams.Query = "EXEC sp_configure 'show advanced option', '1'"
                $mockExpectedQuery = $queryParams.Query.Clone()

                { Invoke-Query @queryParams } | Should -Not -Throw

                Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 1 -Exactly
            }

            It 'Should throw the correct error, ExecuteNonQueryFailed, when executing the query fails' {
                $queryParams.Query = 'BadQuery'

                { Invoke-Query @queryParams } | Should -Throw ($script:localizedData.ExecuteNonQueryFailed -f $queryParams.Database)

                Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 1 -Exactly
            }
        }

        Context 'Execute a query with results' {
            It 'Should execute the query and return a result set' {
                $queryParams.Query = 'SELECT name FROM sys.databases'
                $mockExpectedQuery = $queryParams.Query.Clone()

                Invoke-Query @queryParams -WithResults | Should -Not -BeNullOrEmpty

                Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 1 -Exactly
            }

            It 'Should throw the correct error, ExecuteQueryWithResultsFailed, when executing the query fails' {
                $queryParams.Query = 'BadQuery'

                { Invoke-Query @queryParams -WithResults } | Should -Throw ($script:localizedData.ExecuteQueryWithResultsFailed -f $queryParams.Database)

                Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 1 -Exactly
            }
        }
    }

    Describe "Testing Update-AvailabilityGroupReplica" {
        Context 'When the Availability Group Replica is altered' {
            It 'Should silently alter the Availability Group Replica' {
                $availabilityReplica = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityReplica

                { Update-AvailabilityGroupReplica -AvailabilityGroupReplica $availabilityReplica } | Should -Not -Throw

            }

            It 'Should throw the correct error, AlterAvailabilityGroupReplicaFailed, when altering the Availability Group Replica fails' {
                $availabilityReplica = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityReplica
                $availabilityReplica.Name = 'AlterFailed'

                { Update-AvailabilityGroupReplica -AvailabilityGroupReplica $availabilityReplica } | Should -Throw ($script:localizedData.AlterAvailabilityGroupReplicaFailed -f $availabilityReplica.Name)
            }
        }
    }

    Describe "Testing Test-LoginEffectivePermissions" {

        $mockAllPermissionsPresent = @(
            'Connect SQL',
            'Alter Any Availability Group',
            'View Server State'
        )

        $mockPermissionsMissing = @(
            'Connect SQL',
            'View Server State'
        )

        $mockInvokeQueryClusterServicePermissionsSet = @() # Will be set dynamically in the check

        $mockInvokeQueryClusterServicePermissionsResult = {
            return New-Object -TypeName PSObject -Property @{
                Tables = @{
                    Rows = @{
                        permission_name = $mockInvokeQueryClusterServicePermissionsSet
                    }
                }
            }
        }

        $testLoginEffectivePermissionsParams = @{
            SQLServer = 'Server1'
            SQLInstanceName = 'MSSQLSERVER'
            Login = 'NT SERVICE\ClusSvc'
            Permissions = @()
        }

        BeforeEach {
            Mock -CommandName Invoke-Query -MockWith $mockInvokeQueryClusterServicePermissionsResult -Verifiable
        }

        Context 'When all of the permissions are present' {

            It 'Should return $true when the desired permissions are present' {
                $mockInvokeQueryClusterServicePermissionsSet = $mockAllPermissionsPresent.Clone()
                $testLoginEffectivePermissionsParams.Permissions = $mockAllPermissionsPresent.Clone()

                Test-LoginEffectivePermissions @testLoginEffectivePermissionsParams | Should -Be $true

                Assert-MockCalled -CommandName Invoke-Query -Times 1 -Exactly
            }
        }

        Context 'When a permission is missing' {

            It 'Should return $false when the desired permissions are not present' {
                $mockInvokeQueryClusterServicePermissionsSet = $mockPermissionsMissing.Clone()
                $testLoginEffectivePermissionsParams.Permissions = $mockAllPermissionsPresent.Clone()

                Test-LoginEffectivePermissions @testLoginEffectivePermissionsParams | Should -Be $false

                Assert-MockCalled -CommandName Invoke-Query -Scope It -Times 1 -Exactly
            }

            It 'Should return $false when the specified login has no permissions assigned' {
                $mockInvokeQueryClusterServicePermissionsSet = @()
                $testLoginEffectivePermissionsParams.Permissions = $mockAllPermissionsPresent.Clone()

                Test-LoginEffectivePermissions @testLoginEffectivePermissionsParams | Should -Be $false

                Assert-MockCalled -CommandName Invoke-Query -Scope It -Times 1 -Exactly
            }
        }
    }

    $mockImportModule = {
        if ($Name -ne $mockExpectedModuleNameToImport)
        {
            throw ('Wrong module was loaded. Expected {0}, but was {1}.' -f $mockExpectedModuleNameToImport, $Name[0])
        }
    }

    $mockGetModule = {
        return New-Object -TypeName PSObject -Property @{
            Name = $mockModuleNameToImport
        }
    }

    $mockGetModule_SqlServer_ParameterFilter = {
        $FullyQualifiedName.Name -eq 'SqlServer' -and $ListAvailable -eq $true
    }

    $mockGetModule_SQLPS_ParameterFilter = {
        $FullyQualifiedName.Name -eq 'SQLPS' -and $ListAvailable -eq $true
    }

    Describe 'Testing Import-SQLPSModule' -Tag ImportSQLPSModule {
        BeforeEach {
            Mock -CommandName Push-Location -Verifiable
            Mock -CommandName Pop-Location -Verifiable
            Mock -CommandName Import-Module -MockWith $mockImportModule -Verifiable
            Mock -CommandName New-InvalidOperationException -MockWith $mockThrowLocalizedMessage -Verifiable
        }

        Context 'When module SqlServer exists' {
            $mockModuleNameToImport = 'SqlServer'
            $mockExpectedModuleNameToImport = 'SqlServer'

            It 'Should import the SqlServer module without throwing' {
                Mock -CommandName Get-Module -MockWith $mockGetModule -ParameterFilter $mockGetModule_SqlServer_ParameterFilter -Verifiable

                { Import-SQLPSModule } | Should -Not -Throw

                Assert-MockCalled -CommandName Get-Module -ParameterFilter $mockGetModule_SqlServer_ParameterFilter -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Push-Location -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Pop-Location -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Import-Module -Exactly -Times 1 -Scope It
            }
        }

        Context 'When only module SQLPS exists' {
            $mockModuleNameToImport = 'SQLPS'
            $mockExpectedModuleNameToImport = 'SQLPS'

            It 'Should import the SqlServer module without throwing' {
                Mock -CommandName Get-Module -MockWith $mockGetModule -ParameterFilter $mockGetModule_SQLPS_ParameterFilter -Verifiable
                Mock -CommandName Get-Module -MockWith {
                    return $null
                } -ParameterFilter $mockGetModule_SqlServer_ParameterFilter -Verifiable

                { Import-SQLPSModule } | Should -Not -Throw

                Assert-MockCalled -CommandName Get-Module -ParameterFilter $mockGetModule_SqlServer_ParameterFilter -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Get-Module -ParameterFilter $mockGetModule_SQLPS_ParameterFilter -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Push-Location -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Pop-Location -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Import-Module -Exactly -Times 1 -Scope It
            }
        }

        Context 'When neither SqlServer or SQLPS exists' {
            $mockModuleNameToImport = 'UnknownModule'
            $mockExpectedModuleNameToImport = 'SQLPS'

            It 'Should throw the correct error message' {
                Mock -CommandName Get-Module

                { Import-SQLPSModule } | Should -Throw $script:localizedData.PowerShellSqlModuleNotFound

                Assert-MockCalled -CommandName Get-Module -Exactly -Times 2 -Scope It
                Assert-MockCalled -CommandName Push-Location -Exactly -Times 0 -Scope It
                Assert-MockCalled -CommandName Pop-Location -Exactly -Times 0 -Scope It
                Assert-MockCalled -CommandName Import-Module -Exactly -Times 0 -Scope It
            }
        }

        Context 'When Import-Module fails to load the module' {
            $mockModuleNameToImport = 'SqlServer'
            $mockExpectedModuleNameToImport = 'SqlServer'

            It 'Should throw the correct error message' {
                $errorMessage = 'Mock Import-Module throwing a mocked error.'
                Mock -CommandName Get-Module -MockWith $mockGetModule -ParameterFilter $mockGetModule_SqlServer_ParameterFilter -Verifiable
                Mock -CommandName Import-Module -MockWith {
                    throw $errorMessage
                }

                { Import-SQLPSModule } | Should -Throw ($script:localizedData.FailedToImportPowerShellSqlModule -f $mockExpectedModuleNameToImport)

                Assert-MockCalled -CommandName Get-Module -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Push-Location -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Pop-Location -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Import-Module -Exactly -Times 1 -Scope It
            }
        }

        # This is to test the tests (so the mock throws correctly)
        Context 'When mock Import-Module is called with wrong module name' {
            $mockModuleNameToImport = 'SqlServer'
            $mockExpectedModuleNameToImport = 'UnknownModule'

            It 'Should throw the correct error message' {
                Mock -CommandName Get-Module -MockWith $mockGetModule -ParameterFilter $mockGetModule_SqlServer_ParameterFilter -Verifiable

                { Import-SQLPSModule } | Should -Throw ($script:localizedData.FailedToImportPowerShellSqlModule -f $mockModuleNameToImport)

                Assert-MockCalled -CommandName Get-Module -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Push-Location -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Pop-Location -Exactly -Times 1 -Scope It
                Assert-MockCalled -CommandName Import-Module -Exactly -Times 1 -Scope It
            }
        }

        Assert-VerifiableMock
    }

    $mockGetItemProperty_MicrosoftSQLServer_InstanceNames_SQL = {
        return @(
            (
                New-Object -TypeName Object |
                    Add-Member -MemberType NoteProperty -Name $mockInstanceName -Value $mockInstance_InstanceId -PassThru -Force
            )
        )
    }

    $mockGetItemProperty_MicrosoftSQLServer_FullInstanceId_Setup = {
        return @(
            (
                New-Object -TypeName Object |
                    Add-Member -MemberType NoteProperty -Name 'Version' -Value "$($mockSqlMajorVersion).0.4001.0" -PassThru -Force
            )
        )
    }

    $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_InstanceNames_SQL = {
        $Path -eq 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
    }

    $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_FullInstanceId_Setup = {
        $Path -eq "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$mockInstance_InstanceId\Setup"
    }

    Describe 'Testing Get-SqlInstanceMajorVersion' -Tag GetSqlInstanceMajorVersion {
        BeforeEach {
            Mock -CommandName Get-ItemProperty `
                -ParameterFilter $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_InstanceNames_SQL `
                -MockWith $mockGetItemProperty_MicrosoftSQLServer_InstanceNames_SQL `
                -Verifiable

            Mock -CommandName Get-ItemProperty `
                -ParameterFilter $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_FullInstanceId_Setup `
                -MockWith $mockGetItemProperty_MicrosoftSQLServer_FullInstanceId_Setup `
                -Verifiable
        }

        $mockInstance_InstanceId = "MSSQL$($mockSqlMajorVersion).$($mockInstanceName)"

        Context 'When calling Get-SqlInstanceMajorVersion' {
            It 'Should return the correct major SQL version number' {
                $result = Get-SqlInstanceMajorVersion -SQLInstanceName $mockInstanceName
                $result | Should -Be $mockSqlMajorVersion

                Assert-MockCalled -CommandName Get-ItemProperty -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_InstanceNames_SQL

                Assert-MockCalled -CommandName Get-ItemProperty -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_FullInstanceId_Setup
            }
        }

        Context 'When calling Get-SqlInstanceMajorVersion and nothing is returned' {
            It 'Should throw the correct error' {
                Mock -CommandName Get-ItemProperty `
                    -ParameterFilter $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_FullInstanceId_Setup `
                    -MockWith {
                        return New-Object -TypeName Object
                    } -Verifiable

                $mockCorrectErrorMessage = ($script:localizedData.SqlServerVersionIsInvalid -f $mockInstanceName)
                { Get-SqlInstanceMajorVersion -SQLInstanceName $mockInstanceName } | Should -Throw $mockCorrectErrorMessage

                Assert-MockCalled -CommandName Get-ItemProperty -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_InstanceNames_SQL

                Assert-MockCalled -CommandName Get-ItemProperty -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockGetItemProperty_ParameterFilter_MicrosoftSQLServer_FullInstanceId_Setup
            }
        }

        Assert-VerifiableMock
    }

    $mockApplicationDomainName = 'SqlServerDscHelperTests'
    $mockApplicationDomainObject = [System.AppDomain]::CreateDomain($mockApplicationDomainName)

    <#
        It is not possible to fully test this helper function since we can't mock having the correct assembly
        in the GAC. So these test will try to load the wrong assembly and will catch the error. But that means
        it will never test the rows after if fails to load the assembly.
    #>
    Describe 'Testing Register-SqlSmo' -Tag RegisterSqlSmo {
        BeforeEach {
            Mock -CommandName Get-SqlInstanceMajorVersion -MockWith {
                return '0' # Mocking zero because that could never match a correct assembly
            } -Verifiable
        }

        Context 'When calling Register-SqlSmo to load the wrong assembly' {
            It 'Should throw with the correct error' {
                {
                    Register-SqlSmo -SQLInstanceName $mockInstanceName
                } | Should -Throw 'Exception calling "Load" with "1" argument(s): "Could not load file or assembly ''Microsoft.SqlServer.Smo, Version=0.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91'' or one of its dependencies. The system cannot find the file specified."'

                Assert-MockCalled -CommandName Get-SqlInstanceMajorVersion
            }
        }

        Context 'When calling Register-SqlSmo with a application domain to load the wrong assembly' {
            It 'Should throw with the correct error' {
                {
                    Register-SqlSmo -SQLInstanceName $mockInstanceName -ApplicationDomain $mockApplicationDomainObject
                } | Should -Throw 'Exception calling "Load" with "1" argument(s): "Could not load file or assembly ''Microsoft.SqlServer.Smo, Version=0.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91'' or one of its dependencies. The system cannot find the file specified."'

                Assert-MockCalled -CommandName Get-SqlInstanceMajorVersion
            }
        }

        Assert-VerifiableMock
    }

    <#
        It is not possible to fully test this helper function since we can't mock having the correct assembly
        in the GAC. So these test will try to load the wrong assembly and will catch the error. But that means
        it will never test the rows after if fails to load the assembly.
    #>
    Describe 'Testing Register-SqlWmiManagement' -Tag RegisterSqlWmiManagement {
        BeforeEach {
            Mock -CommandName Get-SqlInstanceMajorVersion -MockWith {
                return '0' # Mocking zero because that could never match a correct assembly
            } -Verifiable

            Mock -CommandName Register-SqlSmo -MockWith {
                [System.AppDomain]::CreateDomain('SqlServerDscHelper')
            } -ParameterFilter {
                $SQLInstanceName -eq $mockInstanceName
            } -Verifiable
        }

        Context 'When calling Register-SqlWmiManagement to load the wrong assembly' {
            It 'Should throw with the correct error' {
                {
                    Register-SqlWmiManagement -SQLInstanceName $mockInstanceName
                } | Should -Throw 'Exception calling "Load" with "1" argument(s): "Could not load file or assembly ''Microsoft.SqlServer.SqlWmiManagement, Version=0.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91'' or one of its dependencies. The system cannot find the file specified."'

                Assert-MockCalled -CommandName Get-SqlInstanceMajorVersion
                Assert-MockCalled -CommandName Register-SqlSmo -Exactly -Times 1 -Scope It -ParameterFilter {
                    $SQLInstanceName -eq $mockInstanceName -and $ApplicationDomain -eq $null
                }
            }
        }

        Context 'When calling Register-SqlWmiManagement with a application domain to load the wrong assembly' {
            It 'Should throw with the correct error' {
                {
                    Register-SqlWmiManagement -SQLInstanceName $mockInstanceName -ApplicationDomain $mockApplicationDomainObject
                } | Should -Throw 'Exception calling "Load" with "1" argument(s): "Could not load file or assembly ''Microsoft.SqlServer.SqlWmiManagement, Version=0.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91'' or one of its dependencies. The system cannot find the file specified."'

                Assert-MockCalled -CommandName Get-SqlInstanceMajorVersion
                Assert-MockCalled -CommandName Register-SqlSmo -Exactly -Times 0 -Scope It -ParameterFilter {
                    $SQLInstanceName -eq $mockInstanceName -and $ApplicationDomain -eq $null
                }

                Assert-MockCalled -CommandName Register-SqlSmo -Exactly -Times 1 -Scope It -ParameterFilter {
                    $SQLInstanceName -eq $mockInstanceName -and $ApplicationDomain.FriendlyName -eq $mockApplicationDomainName
                }
            }
        }

        Assert-VerifiableMock
    }

    <#
        NOTE! This test must be after the tests for Register-SqlSmo and Register-SqlWmiManagement.
        This test unloads the application domain that is used during those tests.
    #>
    Describe 'Testing Unregister-SqlAssemblies' -Tag UnregisterSqlAssemblies {
        Context 'When calling Unregister-SqlAssemblies to unload the assemblies' {
            It 'Should not throw an error' {
                {
                    Unregister-SqlAssemblies -ApplicationDomain $mockApplicationDomainObject
                } | Should -Not -Throw
            }
        }
    }

    Describe 'Testing Get-PrimaryReplicaServerObject' {
        BeforeEach {
            $mockServerObject = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server
            $mockServerObject.DomainInstanceName = 'Server1'

            $mockAvailabilityGroup = New-Object -TypeName Microsoft.SqlServer.Management.Smo.AvailabilityGroup
            $mockAvailabilityGroup.PrimaryReplicaServerName = 'Server1'
        }

        $mockConnectSql = {
            Param
            (
                [Parameter()]
                [System.String]
                $SQLServer,

                [Parameter()]
                [System.String]
                $SQLInstanceName
            )

            $mock = @(
                (
                    New-Object -TypeName Object |
                        Add-Member -MemberType NoteProperty -Name 'DomainInstanceName' -Value $SQLServer -PassThru
                )
            )

            # Type the mock as a server object
            $mock.PSObject.TypeNames.Insert(0,'Microsoft.SqlServer.Management.Smo.Server')

            return $mock
        }

        Mock -CommandName Connect-SQL -MockWith $mockConnectSql -Verifiable

        Context 'When the supplied server object is the primary replica' {
            It 'Should return the same server object that was supplied' {
                $result = Get-PrimaryReplicaServerObject -ServerObject $mockServerObject -AvailabilityGroup $mockAvailabilityGroup

                $result.DomainInstanceName | Should -Be $mockServerObject.DomainInstanceName
                $result.DomainInstanceName | Should -Be $mockAvailabilityGroup.PrimaryReplicaServerName

                Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 0 -Exactly
            }

            It 'Should return the same server object that was supplied when the PrimaryReplicaServerNameProperty is empty' {
                $mockAvailabilityGroup.PrimaryReplicaServerName = ''

                $result = Get-PrimaryReplicaServerObject -ServerObject $mockServerObject -AvailabilityGroup $mockAvailabilityGroup

                $result.DomainInstanceName | Should -Be $mockServerObject.DomainInstanceName
                $result.DomainInstanceName | Should -Not -Be $mockAvailabilityGroup.PrimaryReplicaServerName

                Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 0 -Exactly
            }
        }

        Context 'When the supplied server object is not the primary replica' {
            It 'Should the server object of the primary replica' {
                $mockAvailabilityGroup.PrimaryReplicaServerName = 'Server2'

                $result = Get-PrimaryReplicaServerObject -ServerObject $mockServerObject -AvailabilityGroup $mockAvailabilityGroup

                $result.DomainInstanceName | Should -Not -Be $mockServerObject.DomainInstanceName
                $result.DomainInstanceName | Should -Be $mockAvailabilityGroup.PrimaryReplicaServerName

                Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 1 -Exactly
            }
        }
    }

    Describe 'Testing Test-AvailabilityReplicaSeedingModeAutomatic' {

        BeforeEach {
            $mockSqlVersion = 13
            $mockConnectSql = {
                Param
                (
                    [Parameter()]
                    [System.String]
                    $SQLServer,

                    [Parameter()]
                    [System.String]
                    $SQLInstanceName
                )

                $mock = @(
                    (
                        New-Object -TypeName Object |
                            Add-Member -MemberType NoteProperty -Name 'Version' -Value $mockSqlVersion -PassThru
                    )
                )

                # Type the mock as a server object
                $mock.PSObject.TypeNames.Insert(0,'Microsoft.SqlServer.Management.Smo.Server')

                return $mock
            }

            $mockSeedingMode = 'Manual'
            $mockInvokeQuery = {
                return @{
                    Tables = @{
                        Rows = @{
                            seeding_mode_desc = $mockSeedingMode
                        }
                    }
                }
            }

            Mock -CommandName Connect-SQL -MockWith $mockConnectSql -Verifiable
            Mock -CommandName Invoke-Query -MockWith $mockInvokeQuery -Verifiable
        }

        $testAvailabilityReplicaSeedingModeAutomaticParams = @{
            SQLServer = 'Server1'
            SQLInstanceName = 'MSSQLSERVER'
            AvailabilityGroupName = 'Group1'
            AvailabilityReplicaName = 'Replica2'
        }

        Context 'When the replica seeding mode is manual' {
            # Test SQL 2012 and 2014. Not testing earlier versions because Availability Groups were introduced in SQL 2012.
            foreach ( $instanceVersion in @(11,12) )
            {
                It ( 'Should return $false when the instance version is {0}' -f $instanceVersion ) {
                    $mockSqlVersion = $instanceVersion

                    Test-AvailabilityReplicaSeedingModeAutomatic @testAvailabilityReplicaSeedingModeAutomaticParams | Should -Be $false

                    Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 1 -Exactly
                    Assert-MockCalled -CommandName Invoke-Query -Scope It -Times 0 -Exactly
                }
            }

            # Test SQL 2016 and later
            foreach ( $instanceVersion in @(13,14) )
            {
                It ( 'Should return $false when the instance version is {0} and the replica seeding mode is manual' -f $instanceVersion ) {
                    $mockSqlVersion = $instanceVersion

                    Test-AvailabilityReplicaSeedingModeAutomatic @testAvailabilityReplicaSeedingModeAutomaticParams | Should -Be $false

                    Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 1 -Exactly
                    Assert-MockCalled -CommandName Invoke-Query -Scope It -Times 1 -Exactly
                }
            }
        }

        Context 'When the replica seeding mode is automatic' {
            # Test SQL 2016 and later
            foreach ( $instanceVersion in @(13,14) )
            {
                It ( 'Should return $true when the instance version is {0} and the replica seeding mode is automatic' -f $instanceVersion ) {
                    $mockSqlVersion = $instanceVersion
                    $mockSeedingMode = 'Automatic'

                    Test-AvailabilityReplicaSeedingModeAutomatic @testAvailabilityReplicaSeedingModeAutomaticParams | Should -Be $true

                    Assert-MockCalled -CommandName Connect-SQL -Scope It -Times 1 -Exactly
                    Assert-MockCalled -CommandName Invoke-Query -Scope It -Times 1 -Exactly
                }
            }
        }
    }

    Describe 'Testing Test-ImpersonatePermissions' {
        $mockConnectionContextObject = New-Object -TypeName Microsoft.SqlServer.Management.Smo.ConnectionContext
        $mockConnectionContextObject.TrueLogin = 'Login1'

        $mockServerObject = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server
        $mockServerObject.ComputerNamePhysicalNetBIOS = 'Server1'
        $mockServerObject.ServiceName = 'MSSQLSERVER'
        $mockServerObject.ConnectionContext = $mockConnectionContextObject

        Context 'When impersonate permissions are present for the login' {
            Mock -CommandName Test-LoginEffectivePermissions -MockWith { $true }

            It 'Should return true when the impersonate permissions are present for the login'{
                Test-ImpersonatePermissions -ServerObject $mockServerObject | Should -Be $true

                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 1 -Exactly
            }
        }

        Context 'When impersonate permissions are missing for the login' {
            Mock -CommandName Test-LoginEffectivePermissions -MockWith { $false } -Verifiable

            It 'Should return false when the impersonate permissions are missing for the login'{
                Test-ImpersonatePermissions -ServerObject $mockServerObject | Should -Be $false

                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 1 -Exactly
            }
        }
    }

    Describe 'Testing Connect-SQL' -Tag ConnectSql {
        BeforeEach {
            Mock -CommandName New-InvalidOperationException -MockWith $mockThrowLocalizedMessage -Verifiable
            Mock -CommandName Import-SQLPSModule
            Mock -CommandName New-Object `
                -MockWith $mockNewObject_MicrosoftDatabaseEngine `
                -ParameterFilter $mockNewObject_MicrosoftDatabaseEngine_ParameterFilter `
                -Verifiable
        }

        Context 'When connecting to the default instance using Windows Authentication' {
            It 'Should return the correct service instance' {
                $mockExpectedDatabaseEngineServer = 'TestServer'
                $mockExpectedDatabaseEngineInstance = 'MSSQLSERVER'

                $databaseEngineServerObject = Connect-SQL -SQLServer $mockExpectedDatabaseEngineServer
                $databaseEngineServerObject.ConnectionContext.ServerInstance | Should -BeExactly $mockExpectedDatabaseEngineServer

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftDatabaseEngine_ParameterFilter
            }
        }

        Context 'When connecting to the named instance using Windows Authentication' {
            It 'Should return the correct service instance' {
                $mockExpectedDatabaseEngineServer = $env:COMPUTERNAME
                $mockExpectedDatabaseEngineInstance = $mockInstanceName

                $databaseEngineServerObject = Connect-SQL -SQLInstanceName $mockExpectedDatabaseEngineInstance
                $databaseEngineServerObject.ConnectionContext.ServerInstance | Should -BeExactly "$mockExpectedDatabaseEngineServer\$mockExpectedDatabaseEngineInstance"

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftDatabaseEngine_ParameterFilter
            }
        }

        Context 'When connecting to the named instance using Windows Authentication and different server name' {
            It 'Should return the correct service instance' {
                $mockExpectedDatabaseEngineServer = 'SERVER'
                $mockExpectedDatabaseEngineInstance = $mockInstanceName

                $databaseEngineServerObject = Connect-SQL -SQLServer $mockExpectedDatabaseEngineServer -SQLInstanceName $mockExpectedDatabaseEngineInstance
                $databaseEngineServerObject.ConnectionContext.ServerInstance | Should -BeExactly "$mockExpectedDatabaseEngineServer\$mockExpectedDatabaseEngineInstance"

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftDatabaseEngine_ParameterFilter
            }
        }

        Context 'When connecting to the named instance using Windows Authentication impersonation' {
            It 'Should return the correct service instance' {
                $mockExpectedDatabaseEngineServer = $env:COMPUTERNAME
                $mockExpectedDatabaseEngineInstance = $mockInstanceName

                $testParameters = @{
                    SQLServer = $mockExpectedDatabaseEngineServer
                    SQLInstanceName = $mockExpectedDatabaseEngineInstance
                    SetupCredential = $mockSetupCredential
                }

                $databaseEngineServerObject = Connect-SQL @testParameters
                $databaseEngineServerObject.ConnectionContext.ServerInstance | Should -BeExactly "$mockExpectedDatabaseEngineServer\$mockExpectedDatabaseEngineInstance"
                $databaseEngineServerObject.ConnectionContext.ConnectAsUser | Should -Be $true
                $databaseEngineServerObject.ConnectionContext.ConnectAsUserPassword | Should -BeExactly $mockSetupCredential.GetNetworkCredential().Password
                $databaseEngineServerObject.ConnectionContext.ConnectAsUserName | Should -BeExactly $mockSetupCredential.GetNetworkCredential().UserName
                $databaseEngineServerObject.ConnectionContext.ConnectAsUser | Should -Be $true

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftDatabaseEngine_ParameterFilter
            }
        }

        Context 'When connecting to the default instance using the correct service instance but does not return a correct Database Engine object' {
            It 'Should throw the correct error' {
                $mockExpectedDatabaseEngineServer = $env:COMPUTERNAME
                $mockExpectedDatabaseEngineInstance = $mockInstanceName

                Mock -CommandName New-Object `
                    -ParameterFilter $mockNewObject_MicrosoftDatabaseEngine_ParameterFilter `
                    -Verifiable

                $mockCorrectErrorMessage = ($script:localizedData.FailedToConnectToDatabaseEngineInstance -f $mockExpectedDatabaseEngineServer)
                { Connect-SQL } | Should -Throw $mockCorrectErrorMessage

                Assert-MockCalled -CommandName New-Object -Exactly -Times 1 -Scope It `
                    -ParameterFilter $mockNewObject_MicrosoftDatabaseEngine_ParameterFilter
            }
        }

        Assert-VerifiableMock
    }

    Describe 'Testing Test-SQLDscParameterState' -Tag TestSQLDscParameterState {
        Context -Name 'When passing values' -Fixture {
            It 'Should return true for two identical tables' {
                $mockDesiredValues = @{ Example = 'test' }

                $testParameters = @{
                    CurrentValues = $mockDesiredValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $true
            }

            It 'Should return false when a value is different for [System.String]' {
                $mockCurrentValues = @{ Example = [System.String]'something' }
                $mockDesiredValues = @{ Example = [System.String]'test' }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return false when a value is different for [System.Int32]' {
                $mockCurrentValues = @{ Example = [System.Int32]1 }
                $mockDesiredValues = @{ Example = [System.Int32]2 }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return false when a value is different for [Int16]' {
                $mockCurrentValues = @{ Example = [System.Int16]1 }
                $mockDesiredValues = @{ Example = [System.Int16]2 }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return false when a value is different for [UInt16]' {
                $mockCurrentValues = @{ Example = [System.UInt16]1 }
                $mockDesiredValues = @{ Example = [System.UInt16]2 }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return false when a value is missing' {
                $mockCurrentValues = @{ }
                $mockDesiredValues = @{ Example = 'test' }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return true when only a specified value matches, but other non-listed values do not' {
                $mockCurrentValues = @{ Example = 'test'; SecondExample = 'true' }
                $mockDesiredValues = @{ Example = 'test'; SecondExample = 'false'  }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                    ValuesToCheck = @('Example')
                }

                Test-SQLDscParameterState @testParameters | Should -Be $true
            }

            It 'Should return false when only specified values do not match, but other non-listed values do ' {
                $mockCurrentValues = @{ Example = 'test'; SecondExample = 'true' }
                $mockDesiredValues = @{ Example = 'test'; SecondExample = 'false'  }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                    ValuesToCheck = @('SecondExample')
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return false when an empty hash table is used in the current values' {
                $mockCurrentValues = @{ }
                $mockDesiredValues = @{ Example = 'test'; SecondExample = 'false'  }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return true when evaluating a table against a CimInstance' {
                $mockCurrentValues = @{ Handle = '0'; ProcessId = '1000'  }

                $mockWin32ProcessProperties = @{
                    Handle = 0
                    ProcessId = 1000
                }

                $mockNewCimInstanceParameters = @{
                    ClassName = 'Win32_Process'
                    Property = $mockWin32ProcessProperties
                    Key = 'Handle'
                    ClientOnly = $true
                }

                $mockDesiredValues = New-CimInstance @mockNewCimInstanceParameters

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                    ValuesToCheck = @('Handle','ProcessId')
                }

                Test-SQLDscParameterState @testParameters | Should -Be $true
            }

            It 'Should return false when evaluating a table against a CimInstance and a value is wrong' {
                $mockCurrentValues = @{ Handle = '1'; ProcessId = '1000'  }

                $mockWin32ProcessProperties = @{
                    Handle = 0
                    ProcessId = 1000
                }

                $mockNewCimInstanceParameters = @{
                    ClassName = 'Win32_Process'
                    Property = $mockWin32ProcessProperties
                    Key = 'Handle'
                    ClientOnly = $true
                }

                $mockDesiredValues = New-CimInstance @mockNewCimInstanceParameters

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                    ValuesToCheck = @('Handle','ProcessId')
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return true when evaluating a hash table containing an array' {
                $mockCurrentValues = @{ Example = 'test'; SecondExample = @('1','2') }
                $mockDesiredValues = @{ Example = 'test'; SecondExample = @('1','2')  }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $true
            }

            It 'Should return false when evaluating a hash table containing an array with wrong values' {
                $mockCurrentValues = @{ Example = 'test'; SecondExample = @('A','B') }
                $mockDesiredValues = @{ Example = 'test'; SecondExample = @('1','2')  }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return false when evaluating a hash table containing an array, but the CurrentValues are missing an array' {
                $mockCurrentValues = @{ Example = 'test' }
                $mockDesiredValues = @{ Example = 'test'; SecondExample = @('1','2')  }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }

            It 'Should return false when evaluating a hash table containing an array, but the property i CurrentValues is $null' {
                $mockCurrentValues = @{ Example = 'test'; SecondExample = $null }
                $mockDesiredValues = @{ Example = 'test'; SecondExample = @('1','2')  }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false
            }
        }

        Context -Name 'When passing invalid types for DesiredValues' -Fixture {
            It 'Should throw the correct error when DesiredValues is of wrong type' {
                $mockCurrentValues = @{ Example = 'something' }
                $mockDesiredValues = 'NotHashTable'

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                $mockCorrectErrorMessage = ($script:localizedData.PropertyTypeInvalidForDesiredValues -f $testParameters.DesiredValues.GetType().Name)
                { Test-SQLDscParameterState @testParameters } | Should -Throw $mockCorrectErrorMessage
            }

            It 'Should write a warning when DesiredValues contain an unsupported type' {
                Mock -CommandName Write-Warning -Verifiable

                # This is a dummy type to test with a type that could never be a correct one.
                class MockUnknownType
                {
                    [ValidateNotNullOrEmpty()]
                    [System.String]
                    $Property1

                    [ValidateNotNullOrEmpty()]
                    [System.String]
                    $Property2

                    MockUnknownType()
                    {
                    }
                }

                $mockCurrentValues = @{ Example = New-Object -TypeName MockUnknownType }
                $mockDesiredValues = @{ Example = New-Object -TypeName MockUnknownType }

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                }

                Test-SQLDscParameterState @testParameters | Should -Be $false

                Assert-MockCalled -CommandName Write-Warning -Exactly -Times 1
            }
        }

        Context -Name 'When passing an CimInstance as DesiredValue and ValuesToCheck is $null' -Fixture {
            It 'Should throw the correct error' {
                $mockCurrentValues = @{ Example = 'something' }

                $mockWin32ProcessProperties = @{
                    Handle = 0
                    ProcessId = 1000
                }

                $mockNewCimInstanceParameters = @{
                    ClassName = 'Win32_Process'
                    Property = $mockWin32ProcessProperties
                    Key = 'Handle'
                    ClientOnly = $true
                }

                $mockDesiredValues = New-CimInstance @mockNewCimInstanceParameters

                $testParameters = @{
                    CurrentValues = $mockCurrentValues
                    DesiredValues = $mockDesiredValues
                    ValuesToCheck = $null
                }

                $mockCorrectErrorMessage = $script:localizedData.PropertyTypeInvalidForValuesToCheck
                { Test-SQLDscParameterState @testParameters } | Should -Throw $mockCorrectErrorMessage
            }
        }

        Assert-VerifiableMock
    }

    Describe 'Testing New-WarningMessage' -Tag NewWarningMessage {
        Context -Name 'When writing a localized warning message' -Fixture {
            It 'Should write the error message without throwing' {
                Mock -CommandName Write-Warning -Verifiable

                { New-WarningMessage -WarningType 'NoKeyFound' } | Should -Not -Throw

                Assert-MockCalled -CommandName Write-Warning -Exactly -Times 1
            }
        }

        Context -Name 'When trying to write a localized warning message that does not exists' -Fixture {
            It 'Should throw the correct error message' {
                Mock -CommandName Write-Warning -Verifiable

                { New-WarningMessage -WarningType 'UnknownDummyMessage' } | Should -Throw 'No Localization key found for ErrorType: ''UnknownDummyMessage''.'

                Assert-MockCalled -CommandName Write-Warning -Exactly -Times 0
            }
        }

        Assert-VerifiableMock
    }

    Describe 'Testing New-TerminatingError' -Tag NewWarningMessage {
        Context -Name 'When building a localized error message' -Fixture {
            It 'Should return the correct error record with the correct error message' {

                $errorRecord = New-TerminatingError -ErrorType 'NoKeyFound' -FormatArgs 'Dummy error'
                $errorRecord.Exception.Message | Should -Be 'No Localization key found for ErrorType: ''Dummy error''.'
            }
        }

        Context -Name 'When building a localized error message that does not exists' -Fixture {
            It 'Should return the correct error record with the correct error message' {
                $errorRecord = New-TerminatingError -ErrorType 'UnknownDummyMessage' -FormatArgs 'Dummy error'
                $errorRecord.Exception.Message | Should -Be 'No Localization key found for ErrorType: ''UnknownDummyMessage''.'
            }
        }

        Assert-VerifiableMock
    }

    Describe 'Testing Split-FullSQLInstanceName' {
        Context 'When the "FullSQLInstanceName" parameter is not supplied' {
            It 'Should throw when the "FullSQLInstanceName" parameter is $null' {
                { Split-FullSQLInstanceName -FullSQLInstanceName $null } | Should -Throw
            }

            It 'Should throw when the "FullSQLInstanceName" parameter is an empty string' {
                { Split-FullSQLInstanceName -FullSQLInstanceName '' } | Should -Throw
            }
        }

        Context 'When the "FullSQLInstanceName" parameter is supplied' {
            It 'Should throw when the "FullSQLInstanceName" parameter is "ServerName"' {
                $result = Split-FullSQLInstanceName -FullSQLInstanceName 'ServerName'

                $result.Count | Should -Be 2
                $result.SQLServer | Should -Be 'ServerName'
                $result.SQLInstanceName | Should -Be 'MSSQLSERVER'
            }

            It 'Should throw when the "FullSQLInstanceName" parameter is "ServerName\InstanceName"' {
                $result = Split-FullSQLInstanceName -FullSQLInstanceName 'ServerName\InstanceName'

                $result.Count | Should -Be 2
                $result.SQLServer | Should -Be 'ServerName'
                $result.SQLInstanceName | Should -Be 'InstanceName'
            }
        }
    }

    Describe 'Testing Test-ClusterPermissions' {
        BeforeAll {
            Mock -CommandName Test-LoginEffectivePermissions -MockWith {
                $mockClusterServicePermissionsPresent
            } -Verifiable -ParameterFilter {
                $LoginName -eq $clusterServiceName
            }

            Mock -CommandName Test-LoginEffectivePermissions -MockWith {
                $mockSystemPermissionsPresent
            } -Verifiable -ParameterFilter {
                $LoginName -eq $systemAccountName
            }

            $clusterServiceName = 'NT SERVICE\ClusSvc'
            $systemAccountName= 'NT AUTHORITY\System'
        }

        BeforeEach {
            $mockServerObject = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server
            $mockServerObject.NetName = 'TestServer'
            $mockServerObject.ServiceName = 'MSSQLSERVER'

            $mockLogins = @{
                $clusterServiceName = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $mockServerObject,$clusterServiceName
                $systemAccountName = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $mockServerObject,$systemAccountName
            }

            $mockServerObject.Logins = $mockLogins

            $mockClusterServicePermissionsPresent = $false
            $mockSystemPermissionsPresent = $false
        }

        Context 'When the cluster does not have permissions to the instance' {
            It "Should throw the correct error when the logins '$($clusterServiceName)' or '$($systemAccountName)' are absent" {
                $mockServerObject.Logins = @{}

                { Test-ClusterPermissions -ServerObject $mockServerObject } | Should -Throw ( "The cluster does not have permissions to manage the Availability Group on '{0}\{1}'. Grant 'Connect SQL', 'Alter Any Availability Group', and 'View Server State' to either '$($clusterServiceName)' or '$($systemAccountName)'." -f $mockServerObject.NetName,$mockServerObject.ServiceName )

                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 0 -Exactly -ParameterFilter {
                    $LoginName -eq $clusterServiceName
                }
                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 0 -Exactly -ParameterFilter {
                    $LoginName -eq $systemAccountName
                }
            }

            It "Should throw the correct error when the logins '$($clusterServiceName)' and '$($systemAccountName)' do not have permissions to manage availability groups" {
                { Test-ClusterPermissions -ServerObject $mockServerObject } | Should -Throw ( "The cluster does not have permissions to manage the Availability Group on '{0}\{1}'. Grant 'Connect SQL', 'Alter Any Availability Group', and 'View Server State' to either '$($clusterServiceName)' or '$($systemAccountName)'." -f $mockServerObject.NetName,$mockServerObject.ServiceName )

                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 1 -Exactly -ParameterFilter {
                    $LoginName -eq $clusterServiceName
                }
                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 1 -Exactly -ParameterFilter {
                    $LoginName -eq $systemAccountName
                }
            }
        }

        Context 'When the cluster has permissions to the instance' {
            It "Should return NullOrEmpty when '$($clusterServiceName)' is present and has the permissions to manage availability groups" {
                $mockClusterServicePermissionsPresent = $true

                Test-ClusterPermissions -ServerObject $mockServerObject | Should -Be $true

                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 1 -Exactly -ParameterFilter {
                    $LoginName -eq $clusterServiceName
                }
                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 0 -Exactly -ParameterFilter {
                    $LoginName -eq $systemAccountName
                }
            }

            It "Should return NullOrEmpty when '$($systemAccountName)' is present and has the permissions to manage availability groups" {
                $mockSystemPermissionsPresent = $true

                Test-ClusterPermissions -ServerObject $mockServerObject | Should -Be $true

                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 1 -Exactly -ParameterFilter {
                    $LoginName -eq $clusterServiceName
                }
                Assert-MockCalled -CommandName Test-LoginEffectivePermissions -Scope It -Times 1 -Exactly -ParameterFilter {
                    $LoginName -eq $systemAccountName
                }
            }
        }
    }

    Describe 'Testing Restart-ReportingServicesService' {
        Context 'When restarting a Report Services default instance' {
            BeforeAll {
                $mockServiceName = 'ReportServer'

                Mock -CommandName Restart-Service -Verifiable
                Mock -CommandName Start-Service -Verifiable
                Mock -CommandName Get-Service -MockWith {
                    return @{
                        Name = $mockServiceName
                        DependentServices = @(
                            @{
                                Name = 'DependentService'
                                Status = 'Running'
                                DependentServices = @()
                            }
                        )
                    }
                }
            }

            It 'Should restart the service and dependent service' {
                { Restart-ReportingServicesService -SQLInstanceName 'MSSQLSERVER' } | Should -Not -Throw

                Assert-MockCalled -CommandName Get-Service -ParameterFilter {
                    $Name -eq $mockServiceName
                } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Restart-Service -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Start-Service -Scope It -Exactly -Times 1
            }
        }

        Context 'When restarting a Report Services named instance' {
            BeforeAll {
                $mockServiceName = 'ReportServer$TEST'

                Mock -CommandName Restart-Service -Verifiable
                Mock -CommandName Start-Service -Verifiable
                Mock -CommandName Get-Service -MockWith {
                    return @{
                        Name = $mockServiceName
                        DependentServices = @(
                            @{
                                Name = 'DependentService'
                                Status = 'Running'
                                DependentServices = @()
                            }
                        )
                    }
                }
            }

            It 'Should restart the service and dependent service' {
                { Restart-ReportingServicesService -SQLInstanceName 'TEST' } | Should -Not -Throw

                Assert-MockCalled -CommandName Get-Service -ParameterFilter {
                    $Name -eq $mockServiceName
                } -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Restart-Service -Scope It -Exactly -Times 1
                Assert-MockCalled -CommandName Start-Service -Scope It -Exactly -Times 1
            }
        }
    }

    Describe 'Testing Test-ActiveNode' {
        BeforeAll {
            $mockServerObject = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server

            $failoverClusterInstanceTestCases = @(
                @{
                    ComputerNamePhysicalNetBIOS = $env:COMPUTERNAME
                    Result = $true
                },
                @{
                    ComputerNamePhysicalNetBIOS = 'AnotherNode'
                    Result = $false
                }
            )
        }

        Context 'When function is executed on a standalone instance' {
            BeforeAll {
                $mockServerObject.IsMemberOfWsfcCluster = $false
            }

            It 'Should return "$true"' {
                Test-ActiveNode -ServerObject $mockServerObject | Should Be $true
            }
        }

        Context 'When function is executed on a failover cluster instance (FCI)' {
            BeforeAll {
                $mockServerObject.IsMemberOfWsfcCluster = $true
            }

            It 'Should return "<Result>" when the node name is "<ComputerNamePhysicalNetBIOS>"' -TestCases $failoverClusterInstanceTestCases {
                param
                (
                    $ComputerNamePhysicalNetBIOS,
                    $Result
                )

                $mockServerObject.ComputerNamePhysicalNetBIOS = $ComputerNamePhysicalNetBIOS

                Test-ActiveNode -ServerObject $mockServerObject | Should Be $Result
            }
        }
    }
}
