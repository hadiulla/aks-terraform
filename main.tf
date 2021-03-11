resource "azurerm_resource_group" "kubernetes-lab-rg" {
  name     = "kubernetes-lab-rg"
  location = "East US"
}

resource "azurerm_log_analytics_workspace" "kube-log-ws" {
  name                = "kube-log-ws"
  location            = azurerm_resource_group.kubernetes-lab-rg.location
  resource_group_name = azurerm_resource_group.kubernetes-lab-rg.name
  sku                 = "Free"
  retention_in_days   = 7
}

resource "azurerm_kubernetes_cluster" "kube-lab-cluster" {
  name                = "aks-cluster-1"
  location            = azurerm_resource_group.kubernetes-lab-rg.location
  resource_group_name = azurerm_resource_group.kubernetes-lab-rg.name
  dns_prefix          = "hadilab01"

  default_node_pool {
    name       = "default"
    node_count = 1 
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.kube-log-ws.id
    }
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

################## ISTIO CONFIG #########################

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

data "azurerm_subscription" "current" {
}

resource "local_file" "kube_config" {
  content    = azurerm_kubernetes_cluster.kube-lab-cluster.kube_admin_config_raw
  filename   = ".kube/config"   
}


resource "null_resource" "set-kube-config" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    command = "az aks get-credentials -n ${azurerm_kubernetes_cluster.kube-lab-cluster.name} -g ${azurerm_resource_group.rg.name} --file \".kube/${azurerm_kubernetes_cluster.kube-lab-cluster.name}\" --admin --overwrite-existing"
  }
  depends_on = [local_file.kube_config]
}


resource "kubernetes_namespace" "istio_system" {
  provider = kubernetes.local
  metadata {
    name = "istio-system"
  }
}

resource "kubernetes_secret" "grafana" {
  provider = kubernetes.local
  metadata {
    name      = "grafana"
    namespace = "istio-system"
    labels = {
      app = "grafana"
    }
  }
  data = {
    username   = "admin"
    passphrase = random_password.password.result
  }
  type       = "Opaque"
  depends_on = [kubernetes_namespace.istio_system]
}

resource "kubernetes_secret" "kiali" {
  provider = kubernetes.local
  metadata {
    name      = "kiali"
    namespace = "istio-system"
    labels = {
      app = "kiali"
    }
  }
  data = {
    username   = "admin"
    passphrase = random_password.password.result
  }
  type       = "Opaque"
  depends_on = [kubernetes_namespace.istio_system]
}

resource "local_file" "istio-config" {
  content = templatefile("${path.module}/istio-aks.tmpl", {
    enableGrafana = true
    enableKiali   = true
    enableTracing = true
  })
  filename = ".istio/istio-aks.yaml"
}

resource "null_resource" "istio" {
  triggers = {
    always_run = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "istioctl manifest apply -f \".istio/istio-aks.yaml\" --kubeconfig \".kube/${azurerm_kubernetes_cluster.kube-lab-cluster.name}\""
  }
  depends_on = [kubernetes_secret.grafana, kubernetes_secret.kiali, local_file.istio-config]
}