locals {
  expose_lb = var.server_exposure != "none"

  # Both branches must have the same shape, so every key is always present.
  server_service = {
    type = local.expose_lb ? "LoadBalancer" : "ClusterIP"
    annotations = local.expose_lb ? tomap(merge(
      { "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb" },
      var.server_exposure == "internal-nlb" ? { "service.beta.kubernetes.io/aws-load-balancer-internal" = "true" } : {},
    )) : tomap({})
    loadBalancerSourceRanges = local.expose_lb ? var.allowed_cidrs : []
  }

  # Only components that run 2+ replicas get a PDB. A PDB on a single replica
  # would block node drains during upgrades.
  ha_component = {
    replicas = var.high_availability ? 2 : 1
    pdb = {
      enabled      = var.high_availability
      minAvailable = 1
    }
  }

  values = {
    global = {
      logging = { format = "json", level = "info" }
      # Chart default since 10.0.0, set explicitly so it is not lost in an
      # override. Enforced by the VPC CNI network policy agent.
      networkPolicy = { create = true }
    }

    configs = {
      cm = {
        "admin.enabled"           = var.admin_enabled
        "exec.enabled"            = false
        "users.anonymous.enabled" = false
      }
      params = {
        # TLS is terminated by argocd-server itself.
        "server.insecure" = false
      }
      rbac = {
        # Authenticated users get no permissions unless granted in policy.csv.
        "policy.default" = ""
      }
    }

    dex = { enabled = var.dex_enabled }

    redis-ha = { enabled = var.high_availability }

    redis = {
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }

    controller = {
      replicas = 1
      resources = {
        requests = { cpu = "250m", memory = "512Mi" }
        limits   = { memory = "2Gi" }
      }
    }

    server = merge(local.ha_component, {
      service = local.server_service
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
    })

    repoServer = merge(local.ha_component, {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
    })

    applicationSet = merge(local.ha_component, {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
    })

    notifications = {
      resources = {
        requests = { cpu = "25m", memory = "64Mi" }
        limits   = { memory = "256Mi" }
      }
    }
  }
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.namespace

    labels = {
      # Argo CD components meet "baseline"; warn and audit against
      # "restricted" so drift toward privileged pods is visible.
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  # Roll back automatically if an upgrade does not become healthy.
  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 900
  max_history     = 10
  lint            = true

  # Helm deep-merges these documents in order; extra_values win.
  values = concat(
    [yamlencode(local.values)],
    var.domain == null ? [] : [yamlencode({ global = { domain = var.domain } })],
    var.extra_values,
  )
}

data "kubernetes_service_v1" "argocd_server" {
  count = local.expose_lb ? 1 : 0

  metadata {
    name      = "argocd-server"
    namespace = helm_release.argocd.namespace
  }
}
