data "google_project" "this" {
  project_id = var.project_id
}

locals {
  apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudkms.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]
  gke_service_agent = "service-${data.google_project.this.number}@container-engine-robot.iam.gserviceaccount.com"
}

resource "google_project_service" "this" {
  for_each = toset(local.apis)

  project = var.project_id
  service = each.value

  # Other workloads in the project may depend on these APIs.
  disable_on_destroy = false
}

################################################################################
# Network
################################################################################

resource "google_compute_network" "this" {
  project                         = var.project_id
  name                            = "${var.cluster_name}-vpc"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = false

  depends_on = [google_project_service.this]
}

resource "google_compute_subnetwork" "nodes" {
  project                  = var.project_id
  name                     = "${var.cluster_name}-nodes"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Nodes have no public IPs; Cloud NAT gives them egress.
resource "google_compute_router" "this" {
  project = var.project_id
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project                            = var.project_id
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

################################################################################
# KMS for Secrets (application-layer encryption)
################################################################################

resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = "${var.cluster_name}-gke"
  location = var.region

  depends_on = [google_project_service.this]
}

resource "google_kms_crypto_key" "secrets" {
  name            = "secrets"
  key_ring        = google_kms_key_ring.this.id
  rotation_period = "7776000s" # 90 days

}

resource "google_kms_crypto_key_iam_member" "gke" {
  crypto_key_id = google_kms_crypto_key.secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.gke_service_agent}"
}

################################################################################
# Node service account (least privilege, instead of the Compute default SA)
################################################################################

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${substr(var.cluster_name, 0, 24)}-nodes"
  display_name = "GKE nodes for ${var.cluster_name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/container.defaultNodeServiceAccount",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

################################################################################
# Cluster
################################################################################

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.location

  network         = google_compute_network.this.id
  subnetwork      = google_compute_subnetwork.nodes.id
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # The node pool is managed separately so it can be replaced on its own.
  # (Newer GKE versions can skip the default pool entirely; this form works on
  # every version a release channel may hand out.)
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }
  min_master_version = var.kubernetes_version

  # Dataplane V2 (eBPF) enforces NetworkPolicy, including the policies the
  # Argo CD chart creates.
  datapath_provider = "ADVANCED_DATAPATH"

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = !var.endpoint_public_access
  }

  master_authorized_networks_config {
    gcp_public_cidrs_access_enabled = false

    dynamic "cidr_blocks" {
      for_each = var.endpoint_public_access_cidrs
      content {
        cidr_block   = cidr_blocks.value
        display_name = "admin-${cidr_blocks.key}"
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  database_encryption {
    state    = "ENCRYPTED"
    key_name = google_kms_crypto_key.secrets.id
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  enable_legacy_abac    = false
  enable_shielded_nodes = true

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER", "CONTROLLER_MANAGER", "SCHEDULER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  # Applies to the short-lived default pool too.
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  deletion_protection = var.deletion_protection
  resource_labels     = var.labels

  lifecycle {
    ignore_changes = [node_config, initial_node_count]
  }

  depends_on = [
    google_project_service.this,
    google_kms_crypto_key_iam_member.gke,
    google_project_iam_member.nodes,
  ]
}

resource "google_container_node_pool" "this" {
  project     = var.project_id
  name_prefix = "${var.cluster_name}-"
  cluster     = google_container_cluster.this.id
  location    = var.location

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.node_machine_type
    image_type      = "COS_CONTAINERD"
    disk_type       = "pd-balanced"
    disk_size_gb    = var.node_disk_size_gb
    spot            = var.node_spot
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = var.labels
    resource_labels = var.labels

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Pods see the GKE metadata server (Workload Identity), never the node's
    # own service account credentials.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    kubelet_config {
      insecure_kubelet_readonly_port_enabled = "FALSE"
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [initial_node_count]
  }
}
