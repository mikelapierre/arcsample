param clusterName string
param location string = resourceGroup().location
param agentPublicKey string

resource arcCluster 'Microsoft.Kubernetes/connectedClusters@2022-05-01-preview' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {    
    // distribution: 'aks'
    // infrastructure: 'azure'
    agentPublicKeyCertificate: agentPublicKey
  }
}
