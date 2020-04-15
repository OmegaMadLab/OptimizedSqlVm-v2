# PSModulesDsc

This DSC module manages the installation and configuration of Powershell repositories and repository-based Powershell modules on the system. It will not affect modules installed by default with Powershell. Modules must have a RepositorySourceLocation in order to be managed. It was designed without side-by-side support so that only a single instance of a repository module will be installed.

This project has adopted [this code of conduct](CODE_OF_CONDUCT.md).

## Branches

### master

[![Build status](https://ci.appveyor.com/api/projects/status/y21x31hf7hddf7m1/branch/master?svg=true)](https://ci.appveyor.com/project/kingsleyck/psmodulesdsc/branch/master)
[![codecov](https://codecov.io/gh/kingsleyck/PSModulesDsc/branch/master/graph/badge.svg)](https://codecov.io/gh/kingsleyck/PSModulesDsc/branch/master)

This is the branch containing the latest release -
no contributions should be made directly to this branch.

### dev

[![Build status](https://ci.appveyor.com/api/projects/status/y21x31hf7hddf7m1/branch/dev?svg=true)](https://ci.appveyor.com/project/kingsleyck/psmodulesdsc/branch/dev)
[![codecov](https://codecov.io/gh/kingsleyck/PSModulesDsc/branch/dev/graph/badge.svg)](https://codecov.io/gh/kingsleyck/PSModulesDsc/branch/dev)

This is the development branch
to which contributions should be proposed by contributors as pull requests.
This development branch will periodically be merged to the master branch,
and be released to [PowerShell Gallery](https://www.powershellgallery.com/).

## How to Contribute

If you would like to contribute to this repository, please read the DSC Resource Kit [contributing guidelines](https://github.com/PowerShell/DscResource.Kit/blob/master/CONTRIBUTING.md).

## Resources

* **PowershellModule** Manage Powershell modules on the system.
* **PowershellRepository** Manage PSRepositories in the user context (Default: System).

### PowershellModule

Add or remove repository-based Powershell modules from the system. If RequiredVersion is not specified, and the module is not installed, then the latest version will be installed.

* **Name**: The name of a gallery module.
* **RequiredVersion**: The version of a gallery module desired.
* **Repository**: Which PSRepository to source a module from.
* **Ensure**: Present or absent.

### PowershellRepository

Add, remove or update PSRepositories for the system context. Due to limitations in the PSrepository family of cmdlets, this resource only configures a single user context (default: system).

* **Name**: The name of a PSRepository.
* **InstallationPolicy**: Trusted or Untrusted.
* **SourceLocation**: Specify the module source location Uri.
* **Ensure**: Present or absent.
