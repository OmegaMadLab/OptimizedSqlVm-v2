#Requires -Version 5.0

<#
    .SYNOPSIS
        This module addresses the problem of managing Powershell modules. It was designed specifically to ensure that only a single version
        of a given module is installed in the AllUsers scope when Ensure is Present.

    .PARAMETER Name
        The name of a Powershell module.

    .PARAMETER RequiredVersion
        The version of a Powershell module.

    .PARAMETER Repository
        The location of a Powershell module.
#>

enum Ensure
{
    Absent
    Present
}

[DscResource()]
class PowershellModule
{
    [DscProperty(Key)]
    [string]
    $Name

    [DscProperty()]
    [Ensure]
    $Ensure = "Present"

    [DscProperty()]
    [string]
    $RequiredVersion

    [DscProperty()]
    [string]
    $Repository = "PSGallery"

    [PowershellModule] Get()
    {
        $Module = Get-Module -Name $this.Name -ListAvailable | Where-Object { $_.RepositorySourceLocation }

        if ($Module)
        {
            $this.Name = $Module.Name
            $this.RequiredVersion = $Module.Version
            $this.Repository = $Module.RepositorySourceLocation
        }
        else
        {
            $this.Name = $null
            $this.RequiredVersion = $null
            $this.Repository = $null
        }

        return $this
    }

    [void] Set()
    {
        $PSBoundParameters = $this.GetPSBoundParameters()
        $Modules = Get-Module -Name $this.Name -ListAvailable | Where-Object { $_.RepositorySourceLocation }

        if ($this.Ensure -eq [Ensure]::Present)
        {
            if (-not (Get-PackageProvider | Where-Object { $_.Name -eq "NuGet" -and $_.Version -ge "2.8.5.201" }))
            {
                Write-Verbose -Message "Installing latest NuGet package provider in order to use Install-Module."
                $null = Install-PackageProvider -Name NuGet -Scope AllUsers -MinimumVersion 2.8.5.201 -Force
            }

            if ($this.RequiredVersion -and ($Modules.Version -notcontains $this.RequiredVersion))
            {
                Write-Verbose -Message "Installing module [$($this.Name)]."
                Install-Module @PSBoundParameters -Scope AllUsers -Force
            }
        }

        $PSBoundParameters.Remove('Repository')
        foreach ($Module in $Modules)
        {
            if ($this.Ensure -eq [Ensure]::Present)
            {
                if ($Module.Version -ne $this.RequiredVersion)
                {
                    Write-Verbose -Message "Removing side-by-side module [$($Module.Name)] with version [$($Module.Version)]."
                    Get-InstalledModule @PSBoundParameters | Uninstall-Module -Force
                }
            }
            elseif ($this.Ensure -eq [Ensure]::Absent)
            {
                Write-Verbose -Message "Removing module [$($Module.Name)]."
                Get-InstalledModule @PSBoundParameters | Uninstall-Module -Force
            }
        }
    }

    [bool] Test()
    {
        $Module = Get-Module -Name $this.Name -ListAvailable | Where-Object { $_.RepositorySourceLocation }
        $Result = $true

        if ($this.Ensure -eq [Ensure]::Present)
        {
            if ($Module.Count -ne 1)
            {
                Write-Verbose -Message "Expected a single instance of module [$($this.Name)] but was [$($Module.Count)]."
                $Result = $false
            }

            if ($this.RequiredVersion -and ($Module.Version -ne $this.RequiredVersion))
            {
                Write-Verbose -Message "Expected module version [$($this.RequiredVersion)] but was [$($Module.Version)]."
                $Result = $false
            }

            if ($Module.Name -ne $this.Name)
            {
                Write-Verbose -Message "Expected module [$($this.Name)] but was [$($Module.Name)]."
                $Result = $false
            }
        }
        elseif ($this.Ensure -eq [Ensure]::Absent)
        {
            if ($Module.Count -gt 0)
            {
                Write-Verbose -Message "Expected no instances of module [$($this.Name)] but was [$($Module.Count)]."
                $Result = $false
            }
        }

        return $Result
    }

    # Helper method to mimic PSBoundParameters within class
    [hashtable]GetPSBoundParameters()
    {
        $PSBoundParameters = @{
            Name = $this.Name;
            Repository = $this.Repository;
        }

        if ($this.RequiredVersion)
        {
            $PSBoundParameters["RequiredVersion"] = $this.RequiredVersion
        }

        return $PSBoundParameters
    }
}
