resource "azurerm_resource_group" "kubernetes-lab-rg" {
  name     = "kubernetes-lab-rg"
  location = "East US"
}

resource "azurerm_kubernetes_cluster" "kube-lab-cluster" {
  name                = "aks-cluster-1"
  location            = azurerm_resource_group.kubernetes-lab-rg.location
  resource_group_name = azurerm_resource_group.kubernetes-lab-rg.name
  dns_prefix          = "hadilab01"

  default_node_pool {
    name       = "default"
    node_count = 3
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Development"
  }
}

output "client_certificate" {
  value = azurerm_kubernetes_cluster.kube-lab-cluster.kube_config.0.client_certificate
}

output "kube_config" {
  value = azurerm_kubernetes_cluster.kube-lab-cluster.kube_config_raw
}