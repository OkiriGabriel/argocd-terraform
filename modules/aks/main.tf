data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "${var.cluster_name}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_management_lock" "this" {
  count = var.deletion_protection ? 1 : 0

  name       = "${var.cluster_name}-cannot-delete"
  scope      = azurerm_resource_group.this.id
  lock_level = "CanNotDelete"
  notes      = "Managed by Terraform. Set deletion_protection = false to remove."
}

################################################################################
# Network: VNet, node subnet, NAT gateway for egress
################################################################################

resource "azurerm_virtual_network" "this" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_subnet_cidr]

  # No implicit outbound internet; egress goes through the NAT gateway.
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "nat" {
  name                = "${var.cluster_name}-nat"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "${var.cluster_name}-nat"
  location                = azurerm_resource_group.this.location
  resource_group_name     = azurerm_resource_group.this.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "nodes" {
  subnet_id      = azurerm_subnet.nodes.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

################################################################################
# Identity: the control plane needs to manage the node subnet
################################################################################

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "${var.cluster_name}-cluster"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cluster_network" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

################################################################################
# Logging
################################################################################

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.cluster_name}-logs"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "control-plane"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  # kube-audit-admin skips read-only (get/list) events, which keeps cost down.
  dynamic "enabled_log" {
    for_each = ["kube-apiserver", "kube-audit-admin", "kube-controller-manager", "kube-scheduler", "cluster-autoscaler", "guard"]
    content {
      category = enabled_log.value
    }
  }
}

################################################################################
# Cluster
################################################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  node_resource_group = "${var.cluster_name}-nodes-rg"
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Entra ID only: no static admin kubeconfig, Azure RBAC for authorization.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    tenant_id              = data.azurerm_client_config.current.tenant_id
    admin_group_object_ids = var.admin_group_object_ids
    azure_rbac_enabled     = true
  }

  oidc_issuer_enabled          = true
  workload_identity_enabled    = true
  azure_policy_enabled         = true
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48
  run_command_enabled          = false

  private_cluster_enabled = var.private_cluster

  dynamic "api_server_access_profile" {
    for_each = var.private_cluster ? [] : [1]
    content {
      authorized_ip_ranges = var.endpoint_public_access_cidrs
    }
  }

  # Manual: nodes come from the node pool defined below, not Node Auto
  # Provisioning.
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  default_node_pool {
    name                        = "system"
    temporary_name_for_rotation = "systemtmp"
    vm_size                     = var.node_vm_size
    vnet_subnet_id              = azurerm_subnet.nodes.id
    zones                       = var.zones
    auto_scaling_enabled        = true
    min_count                   = var.node_min_count
    max_count                   = var.node_max_count
    os_sku                      = "AzureLinux"
    os_disk_size_gb             = var.node_os_disk_size_gb
    node_public_ip_enabled      = false
    host_encryption_enabled     = var.host_encryption
    max_pods                    = 110

    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    # Cilium dataplane enforces NetworkPolicy.
    network_data_plane = "cilium"
    network_policy     = "cilium"
    pod_cidr           = var.pod_cidr
    service_cidr       = var.service_cidr
    dns_service_ip     = var.dns_service_ip
    load_balancer_sku  = "standard"
    outbound_type      = "userAssignedNATGateway"
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  tags = var.tags

  lifecycle {
    # The autoscaler owns the node count.
    ignore_changes = [default_node_pool[0].node_count]

    precondition {
      condition     = var.node_min_count <= var.node_max_count
      error_message = "node_min_count must be <= node_max_count."
    }
  }

  depends_on = [
    azurerm_role_assignment.cluster_network,
    azurerm_subnet_nat_gateway_association.nodes,
  ]
}

# Lets the identity running Terraform install Helm charts through Azure RBAC.
resource "azurerm_role_assignment" "deployer_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
