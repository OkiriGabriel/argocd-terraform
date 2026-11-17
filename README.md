# Argo CD on Amazon EKS

Terraform that builds a hardened Amazon EKS cluster and installs [Argo CD](https://argo-cd.readthedocs.io/) with Helm. A small nginx app in this repo is the sample GitOps workload.

> Upgrading a cluster built with the older `modules/eks-argocd` layout? Follow [MIGRATION.md](MIGRATION.md).

## Layout

```text
bootstrap/state-backend/  S3 bucket + KMS key for Terraform state (apply once)
modules/eks/              VPC, EKS control plane, add-ons, node group, IAM, KMS, logs
modules/argocd/           Argo CD Helm release and namespace
dev/                      development stack (2 AZs, single NAT, non-HA Argo CD)
prod/                     production stack (3 AZs, NAT per AZ, HA Argo CD, deletion protection)
argocd/
  bootstrap/              AppProject + Application (apply once with kubectl)
  app/                    sample nginx manifests Argo CD keeps in sync
```

Providers (`aws`, `kubernetes`, `helm`) are configured only in the `dev/` and `prod/` roots. The modules declare what they need and inherit the configuration.

## What gets created

**Network**
- VPC with a public and a private subnet per AZ. Private subnets are `/19` because the VPC CNI gives every pod a VPC IP.
- NAT gateway: one shared in dev, one per AZ in prod.
- Default security group stripped of all rules.
- VPC flow logs to CloudWatch.

**EKS**
- Kubernetes 1.35, `STANDARD` upgrade policy (no surprise extended-support fees).
- API endpoint reachable only from `admin_cidrs` (0.0.0.0/0 is rejected), plus the private endpoint.
- Access entries only (`API` auth mode, no `aws-auth` ConfigMap); extra admins via `cluster_admin_principal_arns`.
- Kubernetes Secrets envelope-encrypted with a rotating customer-managed KMS key.
- All five control plane log types, with retention.
- Add-ons pinned to the AWS default version for the cluster version: `vpc-cni` (own IRSA role, network policy enforcement on), `kube-proxy`, `coredns`.
- Managed node group in private subnets: launch template with IMDSv2 required and hop limit 1 (pods cannot read node credentials), encrypted gp3 root volume, SSM Session Manager instead of SSH, node auto-repair, `create_before_destroy` replacements.
- Deletion protection in prod.

**Argo CD** (chart `10.18.0`, Argo CD v3.6.1)
- Installed with `atomic` upgrades, so a failed upgrade rolls back on its own.
- Values built in HCL and passed through `yamlencode`, not string templates or `set` blocks.
- NetworkPolicies on (enforced by the VPC CNI), Dex off, anonymous access off, exec off, empty default RBAC role, JSON logs, resource requests and limits.
- Prod: HA mode (Redis HA, 2 replicas of server/repo-server/ApplicationSet, PodDisruptionBudgets).
- UI exposed on an NLB limited to `admin_cidrs`. Set `server_exposure = "internal-nlb"` or `"none"` to take it off the internet.
- Namespace labelled with Pod Security Admission (`baseline` enforced, `restricted` warn/audit).

## Prerequisites

- Terraform >= 1.10
- AWS CLI v2, with credentials that can create VPC, IAM, KMS, EKS, CloudWatch and ELB resources. The Kubernetes and Helm providers call `aws eks get-token`, so `aws` must be on `PATH`.
- `kubectl`

```bash
aws sts get-caller-identity
```

## 1. Create the state bucket (once per account)

```bash
cd bootstrap/state-backend
cp terraform.tfvars.example terraform.tfvars   # pick a globally unique bucket_name
terraform init
terraform apply
```

State is versioned, KMS-encrypted, TLS-only and locked with an S3 lockfile, so there is no DynamoDB table. This stack keeps its own small state locally; back it up.

## 2. Deploy an environment

```bash
cd dev                                    # or prod
cp backend.hcl.example backend.hcl        # set bucket
cp terraform.tfvars.example terraform.tfvars
# set admin_cidrs to your egress IP(s), e.g. ["203.0.113.10/32"]

terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan
```

The first apply takes about 20–25 minutes.

```bash
terraform output configure_kubectl        # run the printed command
kubectl get nodes
```

## 3. Open Argo CD

```bash
terraform output argocd_url
terraform output argocd_admin_password_command
```

Username is `admin`. After the first login, change the password and delete the bootstrap secret:

```bash
argocd account update-password
kubectl -n argocd delete secret argocd-initial-admin-secret
```

The certificate is self-signed until you add your own. For a real setup, give Argo CD a DNS name (`domain` on the module), put an ACM certificate in front of it (for example with the AWS Load Balancer Controller), configure SSO through `extra_values`, and set `admin_enabled = false`.

No load balancer? Use `terraform output argocd_port_forward_command`.

## 4. Deploy the sample app

Once this repo is pushed:

```bash
kubectl apply -f ../argocd/bootstrap/project.yaml
kubectl apply -f ../argocd/bootstrap/application.yaml
kubectl -n nginx get svc nginx
```

The `sample-apps` project only allows this repo to deploy into the `nginx` namespace. Auto-sync, prune, self-heal and retry are on. The nginx pods run as non-root with a read-only root filesystem under the `restricted` Pod Security Standard, behind a default-deny NetworkPolicy.

## Customising

Common module inputs:

| Input | Module | Notes |
| --- | --- | --- |
| `kubernetes_version` | eks | One minor version per apply |
| `endpoint_public_access` | eks | `false` for a private-only API (needs VPN/bastion/in-VPC CI) |
| `cluster_admin_principal_arns` | eks | Admin roles, for example SSO or CI |
| `node_instance_types`, `node_capacity_type` | eks | `SPOT` is fine for dev |
| `addon_versions` | eks | Pin add-on versions, for example `{ vpc-cni = "v1.20.0-eksbuild.1" }` |
| `chart_version` | argocd | Read the chart's upgrade notes first |
| `high_availability` | argocd | Needs at least 3 nodes |
| `server_exposure` | argocd | `none`, `internal-nlb`, `internet-nlb` |
| `extra_values` | argocd | Extra Helm values documents (SSO, RBAC, repositories) |

## Upgrades

- **Kubernetes:** raise `kubernetes_version` by one minor version and apply. The node group and add-ons follow in the same apply.
- **Argo CD:** raise `chart_version`, read the [chart upgrade notes](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd#upgrading), plan, apply. Failed upgrades roll back automatically.
- **Providers:** versions are pinned in each root's `versions.tf` and the lock file. Run `terraform init -upgrade`, then refresh the lock for all CI platforms:

  ```bash
  terraform providers lock -platform=darwin_arm64 -platform=darwin_amd64 -platform=linux_amd64 -platform=linux_arm64
  ```

## Tear down

```bash
kubectl delete -f ../argocd/bootstrap/application.yaml   # removes the nginx NLB
cd dev   # or prod
terraform destroy
```

In prod, first set `deletion_protection = false` in `prod/main.tf` and apply.

If destroy hangs on a load balancer, delete leftover `LoadBalancer` Services (`kubectl get svc -A | grep LoadBalancer`) and run `terraform destroy` again.

## CI

`.github/workflows/ci.yml` runs on every pull request:

- `terraform fmt`, `validate` and `tflint` for each root
- `trivy` config scan of Terraform and Kubernetes manifests (HIGH/CRITICAL fail the build; accepted findings live in `.trivyignore` with reasons)
- `kubeconform` against Kubernetes 1.35 schemas

Actions are pinned to commit SHAs.
