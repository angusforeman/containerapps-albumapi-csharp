#ContainerApps initiation and intial deployment script
#Note this is POWERSHELL version 

#interactive login via browser 
Connect-AzAccount -UseDeviceAuthentication

#Setup the Powershell Azure Shell environment 
Connect-AzAccount
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
Install-Module -Name Az.App
Register-AzResourceProvider -ProviderNamespace Microsoft.App
Register-AzResourceProvider -ProviderNamespace Microsoft.OperationalInsights

# set up the specific environment resources 
$ResourceGroup = "ContainerApps"
$Location = "uksouth"
$Environment = "env-album-containerapps"
$APIName="album-api"
$FrontendName="album-ui"
$GITHUB_USERNAME = "angusforeman"
$ACRName = "acaalbumsv2"+$GITHUB_USERNAME

#Create the Container Regsistry
$acr = New-AzContainerRegistry -ResourceGroupName $ResourceGroup -Name $ACRName -Sku Basic -EnableAdminUser

#specify & create the required Log Analytics services needed by Container Apps 
$WorkspaceArgs = @{
    Name = 'my-album-workspace'
    ResourceGroupName = $ResourceGroup
    Location = $Location
    PublicNetworkAccessForIngestion = 'Enabled'
    PublicNetworkAccessForQuery = 'Enabled'
}
New-AzOperationalInsightsWorkspace @WorkspaceArgs
$WorkspaceId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroup -Name $WorkspaceArgs.Name).CustomerId
$WorkspaceSharedKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $ResourceGroup -Name $WorkspaceArgs.Name).PrimarySharedKey

#Create the Contaner App Environment
$EnvArgs = @{
    EnvName = $Environment
    ResourceGroupName = $ResourceGroup
    Location = $Location
    AppLogConfigurationDestination = 'log-analytics'
    LogAnalyticConfigurationCustomerId = $WorkspaceId
    LogAnalyticConfigurationSharedKey = $WorkspaceSharedKey
}

New-AzContainerAppManagedEnv @EnvArgs

#Clone the code and move to the src folder
git clone https://github.com/$GITHUB_USERNAME/containerapps-albumapi-csharp.git code-to-cloud2
cd code-to-cloud2/src
# From here on to create an updated image deployment  ==============================================
#  new Album(7, "Queenies fox songs", "Queenie and the foxettes", 19.99,  "https://aka.ms/albums-containerappslogo")
git pull #- wil get updates if doing incremental


#Build the container 
#NOTE that this image will be built in the src folder (via the . parameter)
az acr build --registry $ACRName --image $APIName .


#Create a template object for the image 
$ImageParams = @{
    Name = $APIName
    Image = $ACRName + '.azurecr.io/' + $APIName + ':latest'
}
$TemplateObj = New-AzContainerAppTemplateObject @ImageParams

#Get the registry credentials 
$RegistryCredentials = Get-AzContainerRegistryCredential -Name $ACRName -ResourceGroupName $ResourceGroup
#Create a registry credential object to define your registry information, and a secret object to define your registry password.
$RegistryArgs = @{
    Server = $ACRName + '.azurecr.io'
    PasswordSecretRef = 'registrysecret'
    Username = $RegistryCredentials.Username
}
$RegistryObj = New-AzContainerAppRegistryCredentialObject @RegistryArgs

$SecretObj = New-AzContainerAppSecretObject -Name 'registrysecret' -Value $RegistryCredentials.Password
#Get your environment ID.
$EnvId = (Get-AzContainerAppManagedEnv -EnvName $Environment -ResourceGroup $ResourceGroup).Id

#Create the container App
$AppArgs = @{
    Name = $APIName
    Location = $Location
    ResourceGroupName = $ResourceGroup
    ManagedEnvironmentId = $EnvId
    TemplateContainer = $TemplateObj
    ConfigurationRegistry = $RegistryObj
    ConfigurationSecret = $SecretObj
    IngressTargetPort = 3500
    IngressExternal = $true
}
$MyApp = New-AzContainerApp @AppArgs

# show the app's fully qualified domain name (FQDN).
$MyApp.IngressFqdn
