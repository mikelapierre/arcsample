$Params = Get-Content ./parameters.txt
$SubscriptionId = $Params[0]
$TenantId = $Params[1]
$ResourceGroupName = $Params[2]
$Location = $Params[3]
$ClusterName = $Params[4]

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

$LastHelmPackage = Invoke-RestMethod "https://$Location.dp.kubernetesconfiguration.azure.com/azure-arc-k8sagents/GetLatestHelmPackagePath?api-version=2019-11-01-preview&releaseTrain=stable" -Method "POST"
$Chart = $LastHelmPackage.repositoryPath
$Chart -match "(?<domain>[^/]+)(?<chart>[^:]+)\:(?<version>[\d\.]+)" | Out-Null

# TODO: Replace with helm pull when it works properly
$ManifestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$ManifestHeaders.Add("Accept", "application/vnd.oci.image.manifest.v1+json")
$Manifest = Invoke-RestMethod "https://$($Matches["domain"])/v2$($Matches["chart"])/manifests/$($Matches["version"])" -Method "GET" -Headers $ManifestHeaders
Invoke-WebRequest -Uri "https://$($Matches["domain"])/v2$($Matches["chart"])/blobs/$($Manifest.layers[0].digest)" -OutFile "azure-arc.tar.gz"
tar -zxvf azure-arc.tar.gz

$Template = [System.IO.File]::ReadAllText("template.yaml")
$Template = $Template.Replace("{{LOCATION}}", $Location)
$Template = $Template.Replace("{{PRIVATE-KEY}}", $AgentPrivateKeyPEM)
$Template = $Template.Replace("{{RESOURCE-GROUP}}", $ResourceGroupName)
$Template = $Template.Replace("{{CLUSTER-NAME}}", $ClusterName)
$Template = $Template.Replace("{{SUBSCRIPTION-ID}}", $SubscriptionId)
$Template = $Template.Replace("{{TENANT-ID}}", $TenantId)
[System.IO.File]::WriteAllText("values.yaml", $Template)

helm upgrade --install azure-arc ./azure-arc-k8sagents -f ./values.yaml --debug