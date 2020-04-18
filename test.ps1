New-AzResourceGroupDeployment -Name "SQLTest" `
    -ResourceGroupName "SqlIaasVmPlayground" `
    -TemplateFile ".\azuredeploy.json" `
    -TemplateParameterFile ".\azuredeploy.parameters.json"

New-AzResourceGroupDeployment -Name "SQLTestCluster" `
    -ResourceGroupName "SqlIaasVmPlayground" `
    -TemplateFile ".\azuredeploy.json" `
    -TemplateParameterFile ".\azuredeploy.parameters.cluster.json"