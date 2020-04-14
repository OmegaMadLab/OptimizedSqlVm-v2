# Optimized SQL Server VM for Azure IaaS

[![Deploy to Azure](http://azuredeploy.net/deploybutton.png)](https://azuredeploy.net/)

This template allows you to deploy a SQL Server on Windows VM on Azure IaaS, following best practices explained on <a href="https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sql/virtual-machines-windows-sql-performance">official documentation</a>.

A DSC resource will execute domain join, if requested.

After the deployment, an Azure Custom Script extension will be launched to:
<ul>
    <li>create SQL optimized storage pools, if striping is enabled for data or log disks</li>
    <li>create SQL optimized volumes</li>
    <li>create folder for data files, log files, backup and errorlog
</ul>

In near future, the template will be able to set SQL Server default paths, move databases from Os disk to data disks and to apply SQL Server optimization like trace flags, max server memory, TempDB multiple data files provisionig.

<table>
    <tr>
        <th>Parameter</th>
        <th>Description</th>
    </tr>
    <tr>
        <td>vmName</td>
        <td>Name assigned to the VM.</td>
    </tr>
    <tr>
        <td>availabilitySetName</td>
        <td>Name of the availability set you want to join; it will be created if it doesn't already exist.<br>
            Leave empty if availability set is not needed.</td>
    </tr>
    <tr>
        <td>adDomain</td>
        <td>DNS name of the AD domain you want to join.<br>
            Leave empty if you don't want to join a domain during provisioning.</td>
    </tr>
    <tr>
        <td>adminUsername</td>
        <td>Admin username for the Virtual Machine. If a domain is specified in the appropriate parameter, this user will be used both for local admin and to join domain.</td>
    </tr>
    <tr>
        <td>adminPassword</td>
        <td>Admin password for the Virtual Machine.</td>
    </tr>
    <tr>
        <td>vnetName</td>
        <td>The existing virtual network you want to connect to.<br>
        Leave empty to create a new ad hoc virtual network.</td>
    </tr>
    <tr>
        <td>vnetResourceGroup</td>
        <td>If using an existing vnet, specify the resource group which contains it.<br>
        Leave empty if you're creating a new ad hoc network.</td>
    </tr>
    <tr>
        <td>subnetName</td>
        <td>The subnet you want to connect to.</td>
    </tr>
    <tr>
        <td>privateIp</td>
        <td>The private IP address assigned to the NIC.<br>
        Specify DHCP to use a dynamically assigned IP address.</td>
    </tr>
    <tr>
        <td>enableAcceleratedNetworking</td>
        <td>Choose YES to enable accelerated networking on VM which supports it.<br>
        <B>Please note that enabling this feature on a virtual machine family that doesn't support it will prevent template from being deployed.</b></td>
    </tr>
    <tr>
        <td>enablePublicIp</td>
        <td>Choose YES to assign a public IP to this VM.
    </tr>
    <tr>
        <td>dnsLabelPrefix</td>
        <td>If a public IP is enabled for this VM, assign a DNS label prefix for it.<br>
        Leave empty if public IP is not enabled.</td>
    </tr>
    <tr>
        <td>sqlVersion</td>
        <td>The Azure Marketplace SQL Server image used as base to deploy this VM.</td>
    </tr>
    <tr>
        <td>vmSize</td>
        <td>The family and size for this VM.</td>
    </tr>
    <tr>
        <td>useAHB</td>
        <td>Choose YES to enable Azure Hybrid Benefits for this VM, and use an already owned Windows Server license on it.<br>
        Choose NO if Windows Server licensing fee must be included on VM cost.
        </td>
    </tr>
    <tr>
        <td>timeZone</td>
        <td>The time zone for this VM.</td>
    </tr>
    <tr>
        <td>osDiskSuffix</td>
        <td>The suffix used to compose the OS disk name.<br>
        Final disk name will be composed as [vmName]-[osDiskSuffix].</td>
    </tr>
    <tr>
        <td>dataDiskSuffix</td>
        <td>The suffix used to compose the additional disk (data, log) name.<br>
        Final disk name will be composed as [vmName]-[dataDiskSuffix][number of the disk, starting with 1].</td>
    </tr>
    <tr>
        <td>storageSKU</td>
        <td>The kind of storage used for this VM.</td>
    </tr>
    <tr>
        <td>workloadType</td>
        <td>The kind of workload which will tipically run on this VM.<br>
        It's used to configure various paramters like stripe size, SQL trace flags, etc.<br>
        <i>This parameter is not yet fully functional in the template; it have impacts only on storage configuration.</i></td>    </tr>
    <tr>
        <td>#ofDataDisks</td>
        <td>Number of managed disks which will host SQL Server data files.<br>
        Cache will be set to 'ReadOnly' for Premium disks or 'None' for Standard disks.</td>
    </tr>
    <tr>
        <td>dataDisksSize</td>
        <td>Size of managed disks which will host SQL Server data files.</td>
    </tr>
    <tr>
        <td>stripeDataDisks</td>
        <td>Choose YES to configure a striped Storage Pool on all data disks.</td>
    </tr>
    <tr>
        <td>#ofLogDisks</td>
        <td>Number of managed disks which will host SQL Server log files.<br>
        Cache will be set to 'None' both for Premium and Standard disks.</td>
    </tr>
    <tr>
        <td>logDisksSize</td>
        <td>Size of managed disks which will host SQL Server log files.</td>
    </tr>
    <tr>
        <td>stripeLogDisks</td>
        <td>Choose YES to configure a striped Storage Pool on all log disks.</td>
    </tr>
        <tr>
        <td>#ofAdditionalDisks</td>
        <td>Number of managed disks which will be used for generic workloads like backup.<br>
        These will be always provisioned as Standard managed disks and cache will be set to 'None'.</td>
    </tr>
    <tr>
        <td>AdditionalDisksSize</td>
        <td>Size of managed disks which will be used for generic workloads like backup.</td>
    </tr>
    <tr>
        <td>diagStorageAccountName</td>
        <td>The name of the storage account used to store diagnostic data for this VM; if it doesn't exist, it will be created.<br>
        Leave it empty to create an ad hoc storage account.</td>
    </tr>
</table>
