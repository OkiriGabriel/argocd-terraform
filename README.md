# Argo CD on AWS, GCP, Azure and DigitalOcean

Terraform that builds a hardened managed Kubernetes cluster on **Amazon EKS**, **Google GKE**, **Azure AKS** or **DigitalOcean DOKS**, installs [Argo CD](https://argo-cd.readthedocs.io/) with Helm, and bootstraps a sample GitOps app. The same Argo CD module and the same app manifests run on every cloud.

> Upgrading an EKS cluster built with the older `modules/eks-argocd` layout? Follow [MIGRATION.md](MIGRATION.md).

## Layout

```text
modules/
  eks/  gke/  aks/  doks/    one hardened cluster module per cloud
  argocd/                    Argo CD + GitOps bootstrap, cloud-aware
envs/
  aws/{dev,prod}             one Terraform root per cloud and environment
  gcp/{dev,prod}
  azure/{dev,prod}
  digitalocean/{dev,prod}
bootstrap/
  aws/ gcp/ azure/ digitalocean/   state bucket per cloud (apply once)
argocd/app/
  base/                      sample nginx app (Kustomize)
  overlays/<cloud>/          per-cloud tweaks Argo CD syncs from
```

Every root is independent: its own state, its own cluster, its own Argo CD. Nothing in the GCP stack needs AWS credentials, and so on.

## What each cloud gets

The same baseline everywhere, built from each cloud's own features:

| Control | AWS (EKS) | GCP (GKE) | Azure (AKS) | DigitalOcean (DOKS) |
| --- | --- | --- | --- | --- |
| API access allowlist (`admin_cidrs`, 0.0.0.0/0 rejected) | Public endpoint CIDRs | Master authorized networks | Authorized IP ranges | Control plane firewall |
| Private API option | `endpoint_public_access = false` | `endpoint_public_access = false` | `private_cluster = true` | — |
| Identity-based cluster auth | EKS access entries | Google IAM | Entra ID + Azure RBAC, local accounts off | DO API token (doctl) |
| Secrets encrypted with your key | KMS | Cloud KMS | Platform-managed (see notes) | Platform-managed |
| Pods can't use node credentials | IMDSv2, hop limit 1, CNI on IRSA | Workload Identity, GKE metadata server | Workload Identity | No node credentials on DO |
| Pod identity for apps | IRSA | Workload Identity | Workload Identity | — |
| NetworkPolicy enforced | VPC CNI policy agent | Dataplane V2 | Cilium | Cilium (built in) |
| Private nodes + NAT egress | Yes | Yes (Cloud NAT) | Yes (NAT gateway) | VPC; nodes have public IPs (DOKS) |
| Control plane / flow logs | CloudWatch + VPC flow logs | Cloud Logging + subnet flow logs | Log Analytics + diagnostic settings | — |
| Automatic patching | Managed node group + add-ons | Release channel + auto-upgrade | `patch` channel + node image | Auto-upgrade in maintenance window |
| Hardened nodes | Encrypted gp3, SSM, auto-repair | Shielded VMs, COS, auto-repair | Azure Linux, no public IPs | — |
| Deletion protection (prod) | EKS deletion protection | GKE deletion protection | Resource group lock | — |
| HA in prod | 3 AZs, NAT per AZ | Regional cluster | 3 zones, Standard tier SLA | HA control plane |

**Argo CD** (chart `10.18.0`, Argo CD v3.6.1) is identical on every cloud:
- `atomic` Helm upgrades that roll back on failure. Values are built in HCL with `yamlencode`.
- NetworkPolicies on, Dex off, anonymous access off, exec off, empty default RBAC role, resource requests and limits.
- HA mode in prod: Redis HA, 2 replicas of the server, repo-server and ApplicationSet controller, plus PodDisruptionBudgets.
- UI on a cloud load balancer limited to `admin_cidrs` through `loadBalancerSourceRanges`, which all four clouds enforce.
- `server_exposure` takes `none`, `internal` (private LB; not on DigitalOcean) or `internet`.
- A Terraform-managed AppProject and Application (via the `argocd-apps` chart) sync `argocd/app/overlays/<cloud>`. The project may only deploy this repo into the `nginx` namespace.

## Prerequisites

All clouds: Terraform >= 1.10 and `kubectl`. Then the CLI for your cloud. The Kubernetes and Helm providers call it for short-lived tokens, so it must be on `PATH`.

| Cloud | Tools | Credentials |
| --- | --- | --- |
| AWS | AWS CLI v2 | `aws sts get-caller-identity` works |
| GCP | `gcloud` + `gke-gcloud-auth-plugin` | `gcloud auth application-default login` |
| Azure | `az` + `kubelogin` | `az login`; you need Owner (or Contributor + User Access Administrator) on the subscription |
| DigitalOcean | `doctl` | `DIGITALOCEAN_TOKEN`; `doctl auth init`; Spaces keys for state (see below) |

## Deploy

Pick a cloud and environment; the steps are the same everywhere.

### 1. Create the state bucket (once per cloud account)

```bash
cd bootstrap/<cloud>              # aws | gcp | azure | digitalocean
cp terraform.tfvars.example terraform.tfvars   # set a unique bucket / account name
terraform init && terraform apply
```

| Cloud | Backend | Locking |
| --- | --- | --- |
| AWS | S3, versioned, KMS, TLS-only | S3 lockfile |
| GCP | GCS, versioned, public access prevented | native |
| Azure | Blob storage, ZRS, versioning + soft delete, shared keys off (Entra ID only) | blob lease |
| DigitalOcean | Spaces via the S3 backend, versioned | S3 lockfile ([DigitalOcean's guide](https://docs.digitalocean.com/products/spaces/reference/terraform-backend/) uses it; test it on your account) |

For DigitalOcean, export your Spaces keys first:
- For `bootstrap/digitalocean`: `SPACES_ACCESS_KEY_ID` and `SPACES_SECRET_ACCESS_KEY`.
- For the environment roots: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (the S3 backend reads these names).

### 2. Apply an environment

```bash
cd envs/<cloud>/dev                       # or prod
cp backend.hcl.example backend.hcl        # bucket/account from step 1
cp terraform.tfvars.example terraform.tfvars
# set admin_cidrs to your egress IP(s), e.g. ["203.0.113.10/32"], plus the
# cloud-specific values (project_id, subscription_id, admin_group_object_ids)

terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

```bash
terraform output configure_kubectl        # run the printed command
kubectl get nodes
```

### 3. Open Argo CD

```bash
terraform output argocd_url
terraform output argocd_admin_password_command
```

Username is `admin`. After the first login, change the password and delete the bootstrap secret:

```bash
argocd account update-password
kubectl -n argocd delete secret argocd-initial-admin-secret
```

The certificate is self-signed until you add your own. For a real setup:
1. Give Argo CD a DNS name (`domain` on the module).
2. Put a certificate in front of it.
3. Configure SSO through `extra_values`.
4. Set `admin_enabled = false`.

### 4. Check the sample app

Terraform already created the Application. Once this repo is pushed, Argo CD syncs it:

```bash
kubectl -n argocd get applications
kubectl -n nginx get svc nginx
```

## Network ranges

Each environment uses non-overlapping ranges, so you can peer or VPN them together later:

| Root | Node network | Pods | Services |
| --- | --- | --- | --- |
| aws/dev | 10.0.0.0/16 | VPC (CNI) | EKS default |
| aws/prod | 10.10.0.0/16 | VPC (CNI) | EKS default |
| gcp/dev | 10.20.0.0/20 | 10.24.0.0/14 | 10.28.0.0/20 |
| gcp/prod | 10.30.0.0/20 | 10.32.0.0/14 | 10.36.0.0/20 |
| azure/dev | 10.40.0.0/16 | 192.168.0.0/16 (overlay) | 172.16.0.0/16 |
| azure/prod | 10.50.0.0/16 | 192.168.0.0/16 (overlay) | 172.16.0.0/16 |
| digitalocean/dev | 10.60.0.0/20 | 10.244.0.0/16 | 10.245.0.0/16 |
| digitalocean/prod | 10.70.0.0/20 | 10.246.0.0/16 | 10.247.0.0/16 |

## Upgrades

- **Kubernetes:**
  - **EKS:** raise `kubernetes_version` one minor version per apply.
  - **GKE:** the release channel upgrades for you. `kubernetes_version` only sets a floor.
  - **AKS:** raise the minor `kubernetes_version`; patches are automatic.
  - **DOKS:** raise the minor `kubernetes_version`; patches are automatic in the maintenance window.
- **Argo CD:** raise `chart_version`, read the [chart upgrade notes](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd#upgrading), plan, apply.
- **Providers:** pinned in each root's `versions.tf` and lock file. After `terraform init -upgrade`, refresh the lock for all CI platforms:

  ```bash
  terraform providers lock -platform=darwin_arm64 -platform=darwin_amd64 -platform=linux_amd64 -platform=linux_arm64
  ```

## Tear down

```bash
cd envs/<cloud>/<env>
terraform destroy
```

Terraform removes the bootstrap Application first. Its finalizer deletes the app's load balancer while the cluster is still there, so no orphaned load balancers block the destroy.

Prod environments are protected. First set `deletion_protection = false` in `main.tf` and apply:
- **AWS and GCP:** the protection is on the cluster.
- **Azure:** it is the resource group lock.

On GCP, KMS key rings cannot be deleted. Recreating an environment with the same name reuses the key ring name, so give a rebuilt cluster a new `cluster_name`.

## Notes and known gaps

- **AKS secrets encryption** uses Azure platform-managed keys. Customer-managed keys (KMS etcd encryption with Key Vault) are not wired up yet.
- **DigitalOcean** has no customer-managed encryption keys, internal load balancers or private nodes. The control plane firewall and `loadBalancerSourceRanges` are the main controls.
- **GKE** uses `remove_default_node_pool`, which google provider 8.x marks deprecated. Its replacement only works on GKE 1.36.4+, so the deprecated form is kept until release channels are all past that version.
- **AWS** environments keep the module name `module.eks` (other clouds use `module.cluster`) so existing state and the migration guide stay valid.

## CI

`.github/workflows/ci.yml` runs on every pull request:

- `terraform fmt`, `validate` and `tflint` (AWS, Google and Azure rulesets) for all 12 roots
- `trivy` config scan of Terraform and Kubernetes manifests; accepted findings live in `.trivyignore` with reasons
- `kubeconform` on every cloud overlay against Kubernetes 1.35 schemas

Actions are pinned to commit SHAs.
