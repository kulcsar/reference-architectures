#
# Deploy_ReferenceArchitecture.ps1
#
param(
  [Parameter(Mandatory=$true)]
  $TenantId,	
  [Parameter(Mandatory=$true)]
  $SubscriptionId,
  [Parameter(Mandatory=$true)]
  $Location,
  [Parameter(Mandatory=$true)]
  [ValidateSet("Step1Infra", "Step2Infra", "Step3Workload", "Step4Security")]
  $Mode
)

$ErrorActionPreference = "Stop"

$templateRootUriString = $env:TEMPLATE_ROOT_URI
if ($templateRootUriString -eq $null) {
  $templateRootUriString = "https://raw.githubusercontent.com/mspnp/template-building-blocks/v1.0.0/"
}

if (![System.Uri]::IsWellFormedUriString($templateRootUriString, [System.UriKind]::Absolute)) {
  throw "Invalid value for TEMPLATE_ROOT_URI: $env:TEMPLATE_ROOT_URI"
}

Write-Host
Write-Host "Using $templateRootUriString to locate templates"
Write-Host

$templateRootUri = New-Object System.Uri -ArgumentList @($templateRootUriString)

$loadBalancerTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/loadBalancer-backend-n-vm/azuredeploy.json")
$virtualNetworkTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/vnet-n-subnet/azuredeploy.json")
$virtualMachineTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/multi-vm-n-nic-m-storage/azuredeploy.json")
$virtualMachineExtensionsTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/virtualMachine-extensions/azuredeploy.json")
$networkSecurityGroupTemplate = New-Object System.Uri -ArgumentList @($templateRootUri, "templates/buildingBlocks/networkSecurityGroups/azuredeploy.json")
$fileshareTemplateFile = [System.IO.Path]::Combine($PSScriptRoot, "templates\filesharestorage.template.json")

# Azure ADDS Parameter Files
$domainControllersParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\adds\ad.parameters.json")
$virtualNetworkDNSParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\adds\virtualNetwork-adds-dns.parameters.json")
$addAddsDomainControllerExtensionParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\adds\add-adds-domain-controller.parameters.json")
$createAddsDomainControllerForestExtensionParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\adds\create-adds-forest-extension.parameters.json")

# SQL Always On Parameter Files
$sqlParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\sql.parameters.json")
$fswParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\fsw.parameters.json")
$sqlPrepareAOExtensionParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\sql-iaas-ao-extensions.parameters.json")
$sqlConfigureAOExtensionParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\sql-configure-ao-extension.parameters.json")

# Infrastructure And Workload Parameters Files
$virtualNetworkParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\virtualNetwork.parameters.json")
$managementParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\virtualMachines-mgmt.parameters.json")
$webLoadBalancerParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\web.parameters.json")
$web2LoadBalancerParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\web2.parameters.json")
$networkSecurityGroupParametersFile = [System.IO.Path]::Combine($PSScriptRoot, "parameters\networkSecurityGroups.parameters.json")

$infrastructureResourceGroupName = "boinfra-network-rg"
$workloadResourceGroupName = "boinfra-workload-rg"

# Login to Azure and select your subscription
Login-AzureRmAccount -TenantId $TenantId -SubscriptionId $SubscriptionId | Out-Null

if ($Mode -eq "Step1Infra") {
    $infrastructureResourceGroup = New-AzureRmResourceGroup -Name $infrastructureResourceGroupName -Location $Location
    Write-Host "Creating virtual network..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-vnet-deployment" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName -TemplateUri $virtualNetworkTemplate.AbsoluteUri `
        -TemplateParameterFile $virtualNetworkParametersFile

	Write-Host "Deploying jumpbox..."
	New-AzureRmResourceGroupDeployment -Name "boinfra-mgmt-deployment" -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName `
    -TemplateUri $virtualMachineTemplate.AbsoluteUri -TemplateParameterFile $managementParametersFile
	
	Write-Host "Deploying ADDS servers..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-ad-deployment" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineTemplate.AbsoluteUri -TemplateParameterFile $domainControllersParametersFile

    Write-Host "Updating virtual network DNS servers..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-update-dns" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName -TemplateUri $virtualNetworkTemplate.AbsoluteUri `
        -TemplateParameterFile $virtualNetworkDNSParametersFile

    Write-Host "Creating ADDS forest..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-primary-ad-ext" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineExtensionsTemplate.AbsoluteUri -TemplateParameterFile $createAddsDomainControllerForestExtensionParametersFile

	Write-Host "Restarting boinfra-ad-vm1..."
	Restart-AzureRmVM -ResourceGroupName $infrastructureResourceGroupName -Name "boinfra-ad-vm1"
	
	Write-Host "Restarting boinfra-ad-vm2..."
	Restart-AzureRmVM -ResourceGroupName $infrastructureResourceGroupName -Name "boinfra-ad-vm2" 

    Write-Host "Creating ADDS domain controller..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-secondary-ad-ext" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineExtensionsTemplate.AbsoluteUri -TemplateParameterFile $addAddsDomainControllerExtensionParametersFile
}
elseif ($Mode -eq "Step2Infra") {	
    $infrastructureResourceGroup = Get-AzureRmResourceGroup -Name $infrastructureResourceGroupName 

	Write-Host "Deploy SQL servers with load balancer..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-servers" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName -TemplateUri $loadBalancerTemplate.AbsoluteUri `
        -TemplateParameterFile $sqlParametersFile

    Write-Host "Deploy FWS..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-fsw" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineTemplate.AbsoluteUri -TemplateParameterFile $fswParametersFile

    Write-Host "Prepare SQL Always ON..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-ao-iaas-ext" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineExtensionsTemplate.AbsoluteUri -TemplateParameterFile $sqlPrepareAOExtensionParametersFile

	Write-Host "Configure SQL Always ON..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-ao-iaas-ext" `
        -ResourceGroupName $infrastructureResourceGroup.ResourceGroupName `
        -TemplateUri $virtualMachineExtensionsTemplate.AbsoluteUri -TemplateParameterFile $sqlConfigureAOExtensionParametersFile
}
elseif ($Mode -eq "Step3Workload") {
    Write-Host "Creating workload resource group..."
    $workloadResourceGroup = New-AzureRmResourceGroup -Name $workloadResourceGroupName -Location $Location

	Write-Host "Deploying Storage account for file share..."
	$fileshareStorageAccountName = "strgbm$(Get-Date -format 'yyyyMMddHHmm')"
	New-AzureRmResourceGroupDeployment -Name "boinfra-fileshare-deployment" `
		-ResourceGroupName $workloadResourceGroup.ResourceGroupName `
		-TemplateFile $fileshareTemplateFile `
		-storageAccountName $fileshareStorageAccountName -accountType "Standard_LRS" -location $Location

	#Get the storage account key
	$storageAccountKey = (Get-AzureRmStorageAccountKey -StorageAccountName $fileshareStorageAccountName -ResourceGroupName $workloadResourceGroupName)[0].Value   
	#Create a context for storage account and key
	$ctx=New-AzureStorageContext -StorageAccountName $fileshareStorageAccountName -StorageAccountKey $storageAccountKey  
	#Create a new file share
	$fileshare = New-AzureStorageShare "share1" -Context $ctx
	$fileshare.Uri
	
	Write-Host "Updating web and web2 parameters..."
	#Get web templates and provide fileShareSettings
	$webLoadBalancerParameterObject = Get-Content $webLoadBalancerParametersFile | Out-String | ConvertFrom-Json
	$web2LoadBalancerParameterObject = Get-Content $web2LoadBalancerParametersFile | Out-String | ConvertFrom-Json
	ForEach ($ext in $webLoadBalancerParameterObject.parameters.virtualMachinesSettings.value.extensions)
	{
		if ($ext.name -eq "map-fileshare") {
			$ext.settingsConfig.fileShareSettings.driveLetter = "X"
			$ext.settingsConfig.fileShareSettings.fileShareUri = $fileshare.Uri
			$ext.settingsConfig.fileShareSettings.storageAccountName = $fileshareStorageAccountName
			$ext.settingsConfig.fileShareSettings.storageAccountKey = $storageAccountKey
		}
	}
	ForEach ($ext in $web2LoadBalancerParameterObject.parameters.virtualMachinesSettings.value.extensions)
	{
		if ($ext.name -eq "map-fileshare") {
			$ext.settingsConfig.fileShareSettings.driveLetter = "X"
			$ext.settingsConfig.fileShareSettings.fileShareUri = $fileshare.Uri
			$ext.settingsConfig.fileShareSettings.storageAccountName = $fileshareStorageAccountName
			$ext.settingsConfig.fileShareSettings.storageAccountKey = $storageAccountKey
		}
	}	
	$webLoadBalancerParameterObject | ConvertTo-Json -Depth 100 | Out-File $webLoadBalancerParametersFile
	$web2LoadBalancerParameterObject | ConvertTo-Json -Depth 100 | Out-File $web2LoadBalancerParametersFile

	Write-Host "Deploy Web servers with load balancer..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-web-deployment" `
        -ResourceGroupName $workloadResourceGroup.ResourceGroupName -TemplateUri $loadBalancerTemplate.AbsoluteUri `
        -TemplateParameterFile $webLoadBalancerParametersFile
	
	Write-Host "Deploy Web2 servers with load balancer..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-web2-deployment" `
        -ResourceGroupName $workloadResourceGroup.ResourceGroupName -TemplateUri $loadBalancerTemplate.AbsoluteUri `
        -TemplateParameterFile $web2LoadBalancerParametersFile
}
elseif ($Mode -eq "Step4Security") {
    $infrastructureResourceGroup = Get-AzureRmResourceGroup -Name $infrastructureResourceGroupName 

    Write-Host "Deploying NSGs..."
    New-AzureRmResourceGroupDeployment -Name "boinfra-nsg-deployment" `
		-ResourceGroupName $infrastructureResourceGroup.ResourceGroupName -TemplateUri $networkSecurityGroupTemplate.AbsoluteUri  `
		-TemplateParameterFile $networkSecurityGroupParametersFile
}