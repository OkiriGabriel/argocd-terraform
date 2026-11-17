locals {
  expose_lb = var.server_exposure != "none"

  # Per-cloud Service annotations. Every cloud here enforces
  # loadBalancerSourceRanges, so the allowlist is the same everywhere.
  lb_annotations = {
    aws = {
      internet = { "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb" }
      internal = {
        "service.beta.kubernetes.io/aws-load-balancer-type"     = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
      }
    }
    gcp = {
      internet = {}
      internal = { "networking.gke.io/load-balancer-type" = "Internal" }
    }
    azure = {
      internet = {}
      internal = { "service.beta.kubernetes.io/azure-load-balancer-internal" = "true" }
    }
    digitalocean = {
      internet = {}
      internal = {}
    }
  }

  # Both branches must have the same shape, so every key is always present.
  server_service = {
    type                     = local.expose_lb ? "LoadBalancer" : "ClusterIP"
    annotations              = local.expose_lb ? tomap(local.lb_annotations[var.cloud][var.server_exposure]) : tomap({})
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

################################################################################
# GitOps bootstrap (AppProject + Application via the argocd-apps chart)
################################################################################

locals {
  bootstrap = var.bootstrap_app == null ? null : {
    projects = {
      (var.bootstrap_app.name) = {
        namespace   = var.namespace
        finalizers  = ["resources-finalizer.argocd.argoproj.io"]
        description = "Managed by Terraform: ${var.bootstrap_app.repo_url}"
        sourceRepos = [var.bootstrap_app.repo_url]
        destinations = [{
          server    = "https://kubernetes.default.svc"
          namespace = var.bootstrap_app.destination_namespace
        }]
        clusterResourceWhitelist = [{ group = "", kind = "Namespace" }]
        namespaceResourceWhitelist = [for k in var.bootstrap_app.allowed_kinds : {
          group = split("/", k)[0]
          kind  = split("/", k)[1]
        }]
      }
    }
    applications = {
      (coalesce(var.bootstrap_app.application_name, var.bootstrap_app.name)) = {
        namespace  = var.namespace
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = var.bootstrap_app.name
        source = {
          repoURL        = var.bootstrap_app.repo_url
          targetRevision = var.bootstrap_app.revision
          path           = var.bootstrap_app.path
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.bootstrap_app.destination_namespace
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["PruneLast=true"]
          retry = {
            limit   = 5
            backoff = { duration = "10s", factor = 2, maxDuration = "3m" }
          }
        }
      }
    }
  }
}

resource "helm_release" "bootstrap" {
  count = var.bootstrap_app == null ? 0 : 1

  name       = "argocd-bootstrap"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.apps_chart_version
  namespace  = helm_release.argocd.namespace

  atomic          = true
  cleanup_on_fail = true
  max_history     = 10
  # Adopt an AppProject/Application with the same name that was created with
  # kubectl before Terraform managed it.
  take_ownership = true

  values = [yamlencode(local.bootstrap)]

  # On destroy this release goes first. The Application finalizer then
  # deletes the app's resources (including its load balancer) while the
  # cluster still exists.
  depends_on = [helm_release.argocd]
}
