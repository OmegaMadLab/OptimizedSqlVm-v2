New-AzResourceGroupDeployment -Name "SQLTest" `
    -ResourceGroupName "SqlIaasVmPlayground" `
    -TemplateFile ".\azuredeploy.json" `
    -TemplateParameterFile ".\azuredeploy.parameters.json"