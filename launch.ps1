$Params = Get-Content ./parameters.txt
$SubscriptionId = $Params[0]
$TenantId = $Params[1]
$ResourceGroupName = $Params[2]
$Location = $Params[3]
$ClusterName = $Params[4]

#az connectedk8s connect --name $ClusterName --resource-group $ResourceGroupName

$RSA = [System.Security.Cryptography.RSA]::Create(4096)
$AgentPublicKey = [System.Convert]::ToBase64String($RSA.ExportRSAPublicKey())
Write-Output "Public key"
Write-Output $AgentPublicKey
Write-Output ""
Write-Output "Private key"
$AgentPrivateKey = [System.Convert]::ToBase64String($RSA.ExportRSAPrivateKey())
Write-Output $AgentPrivateKey

$oPem=new-object System.Text.StringBuilder
$oPem.AppendLine("-----BEGIN RSA PRIVATE KEY-----")
For ($i = 0; $i -lt $AgentPrivateKey.Length; $i+=64) {
    $oPem.AppendLine("    " + $AgentPrivateKey.Substring($i,[System.Math]::Min($AgentPrivateKey.Length-$i,64)))
}
$oPem.Append("    -----END RSA PRIVATE KEY-----")
$AgentPrivateKeyPEM = $oPem.ToString()
Write-Output ""
Write-Output $AgentPrivateKeyPEM

az group create --name $ResourceGroupName --location $Location
az deployment group create `
  --name arc-deploy `
  --resource-group $ResourceGroupName `
  --template-file ./arc.bicep `
  --parameters clusterName=$ClusterName agentPublicKey=$AgentPublicKey

# Only on OpenShift: oc adm policy add-scc-to-user privileged system:serviceaccount:azure-arc:azure-arc-kube-aad-proxy-sa
# Only for Helm<3.8: Set-Item -Path Env:HELM_EXPERIMENTAL_OCI -Value 1 
#helm pull "mcr.microsoft.com/azurearck8s/batch1/stable/azure-arc-k8sagents:1.7.4"
#curl -L https://mcr.microsoft.com/v2/azurearck8s/batch1/stable/azure-arc-k8sagents/blobs/sha256:7fc94ec9f88092bfd61fd2cadcea7814b87b9325f5df4b3f61d11a479e3f727a --output arc.tar.gz
#extract

$Template = [System.IO.File]::ReadAllText("template.yaml")
$Template = $Template.Replace("{{LOCATION}}", $Location)
$Template = $Template.Replace("{{PRIVATE-KEY}}", $AgentPrivateKeyPEM)
$Template = $Template.Replace("{{RESOURCE-GROUP}}", $ResourceGroupName)
$Template = $Template.Replace("{{CLUSTER-NAME}}", $ClusterName)
$Template = $Template.Replace("{{SUBSCRIPTION-ID}}", $SubscriptionId)
$Template = $Template.Replace("{{TENANT-ID}}", $TenantId)
[System.IO.File]::WriteAllText("values.yaml", $Template)

helm upgrade --install azure-arc ./azure-arc-k8sagents -f ./values.yaml --debug

# helm upgrade --install azure-arc ./azure-arc-k8sagents `
#   --set global.subscriptionId=$SubscriptionId `
#   --set global.resourceGroupName=$ResourceGroupName `
#   --set global.resourceName=$ClusterName  `
#   --set global.tenantId=$TenantId `
#   --set global.location=$Location `
#   --set "global.onboardingPrivateKey=$AgentPrivateKey" `
#   --set systemDefaultValues.spnOnboarding=false