data "digitalocean_kubernetes_versions" "this" {
  version_prefix = "${var.kubernetes_version}."
}

resource "digitalocean_vpc" "this" {
  name     = "${var.cluster_name}-vpc"
  region   = var.region
  ip_range = var.vpc_cidr
}

resource "digitalocean_kubernetes_cluster" "this" {
  name   = var.cluster_name
  region = var.region
  # Newest patch of the requested minor; matches what auto_upgrade installs.
  version        = data.digitalocean_kubernetes_versions.this.latest_version
  vpc_uuid       = digitalocean_vpc.this.id
  cluster_subnet = var.cluster_subnet
  service_subnet = var.service_subnet
  ha             = var.ha_control_plane

  # Patch upgrades in the maintenance window; surge keeps capacity up while
  # nodes are replaced.
  auto_upgrade  = true
  surge_upgrade = true

  maintenance_policy {
    day        = var.maintenance_day
    start_time = var.maintenance_start_time
  }

  # Only listed CIDRs can reach the Kubernetes API.
  control_plane_firewall {
    enabled           = true
    allowed_addresses = var.endpoint_public_access_cidrs
  }

  node_pool {
    name       = "${var.cluster_name}-default"
    size       = var.node_size
    auto_scale = true
    min_nodes  = var.node_min_count
    max_nodes  = var.node_max_count
    tags       = var.tags
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = data.digitalocean_kubernetes_versions.this.latest_version != null && data.digitalocean_kubernetes_versions.this.latest_version != ""
      error_message = "DOKS does not offer Kubernetes ${var.kubernetes_version}. Run `doctl kubernetes options versions` for the supported list."
    }
  }
}
