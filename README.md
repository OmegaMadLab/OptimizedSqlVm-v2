# Optimized SQL Server VM for Azure IaaS - v2

[![Deploy to Azure](http://azuredeploy.net/deploybutton.png)](https://azuredeploy.net/)

This template allows you to deploy a Windows VM with SQL Server on Azure IaaS, following best practices explained on the [official documentation](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sql/virtual-machines-windows-sql-performance).

It's an evolution of my [previous template](https://github.com/OmegaMadLab/OptimizedSqlVm). By leveraging the SQL Server Resource Provider, it manages the majority of the tasks that I previously governed via a Custom Script Extension.
The SQL Server Resource Provider provides:

- SQL-optimized storage configuration
- the placement of databases  

A DSC resource will execute domain join and some other tasks, if requested. More optimization will be delivered in the future, to reproduce all the settings I was applying in my previous template.

The template isn't yet tested on all the possible scenarios, please report me any issue.

## Parameters

Parameter|Description
---------|-----------
**vmName**|Name assigned to the VM.
**createAvailabilitySet**|If Yes, a new availability set will be created with the name specified with the *availabilitySetName* parameter.
**availabilitySetName**|Name of the availability set you want to join. Leave empty if availability set is not needed.
**adDomain**|DNS name of the AD domain you want to join. Leave empty if you don't want to join a domain during provisioning.
**adminUsername**|Admin username for the Virtual Machine. If a domain is specified in the appropriate parameter, this user will be used both for local admin and to join domain.
**adminPassword**|Admin password for the Virtual Machine.
**vnetName**|The existing virtual network you want to connect to. Leave empty to create a new ad hoc virtual network.
**vnetResourceGroup**|If using an existing vnet, specify the resource group which contains it. Leave empty if you're creating a new ad hoc network.
**subnetName**|The subnet you want to connect to.
**privateIp**|The private IP address assigned to the NIC. Specify DHCP to use a dynamically assigned IP address.
**enableAcceleratedNetworking**|Choose YES to enable accelerated networking on VM which supports it. **Please note that enabling this feature on a virtual machine family that doesn't support it will prevent template from being deployed.**
**enablePublicIp**|Choose YES to assign a public IP to this VM.
**dnsLabelPrefix**|If a public IP is enabled for this VM, assign a DNS label prefix for it. Leave empty if public IP is not enabled.
**asgIds**|Array of Application Security Groups where the VM must be inserted into. Leave empty if not necessary.
**sqlVersion**|The Azure Marketplace SQL Server image used as base to deploy this VM.
**vmSize**|The family and size for this VM.
**useAHBforWindows**|Choose YES to enable Azure Hybrid Benefits for this VM, and use an already owned Windows Server license on it. Choose NO if Windows Server licensing fee must be included on VM cost.
**timeZone**|The time zone for this VM.
**osDiskSuffix**|The suffix used to compose the OS disk name. Final disk name will be composed as *[vmName-osDiskSuffix]*.
**osDiskStorageSKU**|The kind of storage used for OS disk used by this VM. Values can be *Standard_LRS*, *StandardSSD_LRS*, *Premium_LRS*
**additionalDiskSuffix**|The suffix used to compose the additional disk (data, log, backup) name. Final disk name will be composed as *[vmName]-[dataDiskSuffix][number of the disk, starting with 1]*
**workloadType**|The kind of workload which will tipically run on this VM. It's used to configure various paramters like stripe size, SQL trace flags, etc.
**dataDiskStorageSKU**|The kind of storage used for data disks used by this VM. Values can be *Standard_LRS*, *StandardSSD_LRS*, *Premium_LRS*, *UltraSSD_LRS*. Please note that storage sku backup disks is governed by a template variable.
**#ofDataDisks**|Number of managed disks which will host SQL Server data files. Cache will be set to 'ReadOnly' for Premium disks or 'None' for Standard disks.
**dataDisksSize**|Size of managed disks which will host SQL Server data files.
**logDiskStorageSKU**|The kind of storage used for log disks used by this VM. Values can be *Standard_LRS*, *StandardSSD_LRS*, *Premium_LRS*, *UltraSSD_LRS*. Please note that storage sku backup disks is governed by a template variable.
**#ofLogDisks**|Number of managed disks which will host SQL Server log files. Cache will be set to 'None' both for Premium and Standard disks.
**logDisksSize**|Size of managed disks which will host SQL Server log files.
**#ofAdditionalDisks**|Number of managed disks which will be used for generic workloads like backup. These will be always provisioned as Standard managed disks and cache will be set to 'None'.
**AdditionalDisksSize**|Size of managed disks which will be used for generic workloads like backup.
**dataFilePath**| File path used for SQL DB data files.
**logFilePath**| File path used for SQL DB log files.
**tempFilePath**| File path used for the TempDB.
**sqlTcpPort**| The TCP port used by the SQL Server instance.
**sqlAuthAdmin**| If you specify an userID here, SQL Authentication is enabled on the instance and this user will be used as SA account.
**sqlAuthAdminPassword**| If SQL Authentication is required, specify a password for the SA account.
**sqlRpInstallMode**| Installation mode for the SQL Server Resource Provider. "Full" is recommended for single VM or Availability Group clusters. "LightWeight" is recommended for SQL FCI installation.
**prepareForHA**| If set to AG, the Failover Clusters Windows feature and related administration tools are installed on the VM; if set to FCI, WFSC is installed and the default SQL Server instance provisioned with the image is removed to allow the setup of a new clustered instance. When this parameter is set to FCI, the sqlRpInstallMode parameter is ignored and the SQL RP is installed automatically in LightWeight mode.
**diagStorageAccountName**|The name of the storage account used to store diagnostic data for this VM; if it doesn't exist, it will be created. Leave it empty to create an ad hoc storage account.
**EnableSqlIaasExtension**|Choose YES to install the official SQL IaaS Extension on the VM. It currently works only on default instances, so if you plan to deploy a named instance you can choose NO to avoid its deployment.
**_artifactsLocation**| The public repository where DSC configurations and other artifacts are located.
