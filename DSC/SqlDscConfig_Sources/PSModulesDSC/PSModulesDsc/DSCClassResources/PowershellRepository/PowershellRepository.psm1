#Requires -Version 5.0

<#
    .SYNOPSIS
        This module configures PSRepositories for a single user context (default: system).

    .PARAMETER Name
        The name of a PSRepository.

    .PARAMETER InstallationPolicy
        Set the repository as Trusted or Untrusted.

    .PARAMETER SourceLocation
        The uri that specifies the repository location. If Ensure is Present and the repository
        does not exist, this parameter becomes mandatory.
#>

enum Ensure
{
    Absent
    Present
}

enum InstallationPolicy
{
    Trusted
    Untrusted
}

[DscResource()]
class PowershellRepository
{
    [DscProperty(Key)]
    [string]
    $Name

    [DscProperty()]
    [Ensure]
    $Ensure = "Present"

    [DscProperty()]
    [string]
    $InstallationPolicy

    [DscProperty()]
    [string]
    $SourceLocation

    [PowershellRepository] Get()
    {
        $Repository = Get-PSRepository -Name $this.Name -ErrorAction SilentlyContinue

        if ($Repository)
        {
            $this.Name = $Repository.Name
            $this.InstallationPolicy = $Repository.InstallationPolicy
            $this.SourceLocation = $Repository.SourceLocation
        }
        else
        {
            $this.Name = $null
            $this.InstallationPolicy = $null
            $this.SourceLocation = $null
        }

        return $this
    }

    [void] Set()
    {
        $PSBoundParameters = $this.GetPSBoundParameters()
        $Repository = Get-PSRepository -Name $this.Name -ErrorAction SilentlyContinue
        $Count = ($Repository | Measure-Object).Count

        if ($this.Ensure -eq [Ensure]::Present)
        {
            if (-not (Get-PackageProvider | Where-Object { $_.Name -eq "NuGet" -and $_.Version -ge "2.8.5.201" }))
            {
                Write-Verbose -Message "Installing latest NuGet package provider in order to use Register-PSRepository."
                $null = Install-PackageProvider -Name NuGet -Scope AllUsers -MinimumVersion 2.8.5.201 -Force
            }

            if ($Count -ne 1)
            {
                Write-Verbose -Message "Registering repository [$($this.Name)]."

                if ($this.Name -eq "PSGallery")
                {
                    $PSBoundParameters.Remove("SourceLocation")
                    $PSBoundParameters.Remove("Name")
                    Register-PSRepository -Default @PSBoundParameters
                }
                else
                {
                    Register-PSRepository @PSBoundParameters
                }
            }
            elseif ($this.SourceLocation -and $Repository -and ($Repository.SourceLocation -ne $this.SourceLocation))
            {
                Write-Verbose -Message "Re-register repository [$($this.Name)] to have SourceLocation [$($this.SourceLocation)]."

                Unregister-PSRepository -Name $Repository.Name

                if ($this.Name -eq "PSGallery")
                {
                    $PSBoundParameters.Remove("SourceLocation")
                    $PSBoundParameters.Remove("Name")
                    Register-PSRepository -Default @PSBoundParameters
                }
                else
                {
                    Register-PSRepository @PSBoundParameters
                }
            }
            elseif ($this.InstallationPolicy -and ($Repository.InstallationPolicy -ne $this.InstallationPolicy))
            {
                Write-Verbose -Message "Configuring repository [$($this.Name)] to have InstallationPolicy [$($this.InstallationPolicy)]."
                Set-PSRepository @PSBoundParameters
            }
        }
        elseif ($this.Ensure -eq [Ensure]::Absent)
        {
            if ($Count -gt 0)
            {
                Write-Verbose -Message "Unregister repository [$($this.Name)]."

                Unregister-PSRepository $this.Name
            }
        }
    }

    [bool] Test()
    {
        $Repository = Get-PSRepository -Name $this.Name -ErrorAction SilentlyContinue
        $Count = ($Repository | Measure-Object).Count
        $Result = $true

        if ($this.Ensure -eq [Ensure]::Present)
        {
            if ($Count -ne 1)
            {
                if (-not $this.SourceLocation -and ($this.Name -ne "PSGallery"))
                {
                    throw "SourceLocation is required when the PSRepository does not currently exist."
                }

                Write-Verbose -Message "Expected a single instance of repository [$($this.Name)] but was [$($Count)]."
                $Result = $false
            }

            if ($this.InstallationPolicy -and ($Repository.InstallationPolicy -ne $this.InstallationPolicy))
            {
                Write-Verbose -Message "Expected repository [$($this.Name)] to have InstallationPolicy [$($this.InstallationPolicy)] but was [$($Repository.InstallationPolicy)]."
                $Result = $false
            }

            if ($this.SourceLocation -and ($Repository.SourceLocation -ne $this.SourceLocation))
            {
                Write-Verbose -Message "Expected repository [$($this.Name)] to have SourceLocation [$($this.SourceLocation)] but was [$($Repository.SourceLocation)]."
                $Result = $false
            }
        }
        elseif ($this.Ensure -eq [Ensure]::Absent)
        {
            if ($Count -ne 0)
            {
                Write-Verbose -Message "Expected no instance of repository [$($this.Name)] but was [$($Count)]."
                $Result = $false
            }
        }

        return $Result
    }

    # Helper method to output PSBoundParameters in a familiar way
    [hashtable]GetPSBoundParameters()
    {
        $PSBoundParameters = @{
            Name = $this.Name;
        }

        if ($this.SourceLocation)
        {
            $PSBoundParameters["SourceLocation"] = $this.SourceLocation
        }

        if ($this.InstallationPolicy)
        {
            $PSBoundParameters["InstallationPolicy"] = $this.InstallationPolicy
        }

        return $PSBoundParameters
    }
}
