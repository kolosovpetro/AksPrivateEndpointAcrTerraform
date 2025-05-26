data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

#################################################################################################################
# LOCALS
#################################################################################################################

locals {
  vnet_cidr           = ["10.10.0.0/24"]
  acr_subnet_cidr     = ["10.10.0.0/25"]
}

#################################################################################################################
# RESOURCE GROUP
#################################################################################################################

resource "azurerm_resource_group" "public" {
  location = var.location
  name     = "rg-aks-acr-pe-${var.prefix}"
  tags     = var.tags
}

#################################################################################################################
# VNET AND SUBNET
#################################################################################################################

resource "azurerm_virtual_network" "public" {
  name                = "vnet-${var.prefix}"
  address_space       = local.vnet_cidr
  location            = azurerm_resource_group.public.location
  resource_group_name = azurerm_resource_group.public.name
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks-${var.prefix}"
  resource_group_name  = azurerm_resource_group.public.name
  virtual_network_name = azurerm_virtual_network.public.name
  address_prefixes     = local.acr_subnet_cidr
}

#################################################################################################################
# ACR
#################################################################################################################

resource "azurerm_container_registry" "acr" {
  name                          = "acr${var.prefix}"
  resource_group_name           = azurerm_resource_group.public.name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  network_rule_bypass_option    = "None" #allow trusted Azure services to access a network restricted Container Registry

  network_rule_set {
    default_action = "Deny"
  }
}

#################################################################################################################
# PRIVATE ENDPOINT
#################################################################################################################

resource "azurerm_private_endpoint" "acr_pe" {
  name                = "acr-private-endpoint"
  location            = var.location
  resource_group_name = azurerm_resource_group.public.name
  subnet_id           = azurerm_subnet.aks.id

  private_service_connection {
    name                           = "acr-privatesc"
    private_connection_resource_id = azurerm_container_registry.acr.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }
}

#################################################################################################################
# PRIVATE DNS ZONE
#################################################################################################################

resource "azurerm_private_dns_zone" "acr_dns" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.public.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr_dns_link" {
  name                  = "acr-dns-link-${var.prefix}"
  resource_group_name   = azurerm_resource_group.public.name
  private_dns_zone_name = azurerm_private_dns_zone.acr_dns.name
  virtual_network_id    = azurerm_virtual_network.public.id
}

resource "azurerm_private_dns_a_record" "acr_dns_record" {
  name                = azurerm_container_registry.acr.name
  zone_name           = azurerm_private_dns_zone.acr_dns.name
  resource_group_name = azurerm_resource_group.public.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.acr_pe.private_service_connection[0].private_ip_address]
}

#################################################################################################################
# AKS
#################################################################################################################

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${var.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.public.name
  dns_prefix          = "aks-${var.prefix}"

  default_node_pool {
    name                        = "default"
    node_count                  = 3
    vm_size                     = "Standard_DS2_v2"
    vnet_subnet_id              = azurerm_subnet.aks.id
    temporary_name_for_rotation = "rotationpool"

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
}

resource "azurerm_network_security_group" "aks_block_egress" {
  name                = "aks-egress-deny"
  resource_group_name = azurerm_resource_group.public.name
  location            = azurerm_resource_group.public.location

  security_rule {
    name                       = "deny-egress-all"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks_block_egress.id

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

data "azurerm_kubernetes_cluster" "aks" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_resource_group.public.name

  depends_on = [
    azurerm_kubernetes_cluster.aks
  ]
}

#################################################################################################################
# RBAC
#################################################################################################################

resource "azurerm_role_assignment" "aks_to_acr" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = data.azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}
