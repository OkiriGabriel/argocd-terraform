# Migrating from the `eks-argocd` module

This guide covers an **AWS** cluster that was **already applied** with the old layout (commit `83281ae` or earlier: a single `modules/eks-argocd` module, Terraform state on local disk). If you are deploying fresh (on any cloud), skip this file and follow the README.

The environment folders moved from `dev/` and `prod/` to `envs/aws/dev` and `envs/aws/prod`. Only the folder moved; resource addresses and the state key are unchanged, so no state operations are needed for that move.

## What changed

| Area | Before | After |
| --- | --- | --- |
| Module layout | One `eks-argocd` module that also configured its own `helm`/`kubernetes` providers | `modules/eks` and `modules/argocd`; providers are configured once per environment root |
| Providers | aws 5.x, helm 2.x, kubernetes 2.x | aws 6.x, helm 3.x, kubernetes 3.x |
| Terraform | >= 1.5 | >= 1.10 (needed for S3 native locking) |
| State | Local `terraform.tfstate` | S3, versioned, KMS-encrypted, `use_lockfile` locking (no DynamoDB) |
| Kubernetes | 1.32 (extended support, extra cost) | 1.35 |
| API endpoint | Public, open to `0.0.0.0/0` | Public, limited to `admin_cidrs` (or private only) |
| Auth | `API_AND_CONFIG_MAP` | `API` (access entries only) |
| Secrets | Not envelope-encrypted | Encrypted with a customer-managed KMS key |
| Control plane logs | `api`, `authenticator`, no retention | All five types, retention set |
| VPC CNI | Uses the node role | Own IRSA role, network policy enforcement on |
| Nodes | Default launch template | IMDSv2 only, hop limit 1, encrypted gp3, SSM instead of SSH, auto-repair |
| Node role | `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy` | `AmazonEC2ContainerRegistryPullOnly`, no CNI policy |
| Argo CD chart | 10.9.0 (v3.5), `set` blocks | 10.18.0 (v3.6.1), values via `yamlencode`, atomic upgrades |
| Argo CD exposure | Public NLB open to everyone | NLB limited to `admin_cidrs` (`server_exposure = "internet"`) |
| GitOps bootstrap | `kubectl apply` of an Application | Terraform-managed AppProject + Application (`argocd-apps` chart) |
| Folders | `dev/`, `prod/` | `envs/aws/dev`, `envs/aws/prod` |
| Sample app | `default` namespace, root nginx, `default` project | `nginx` namespace (PSA restricted), non-root nginx, scoped `AppProject` |

`envs/aws/dev/moved.tf` and `envs/aws/prod/moved.tf` map every old resource address to its new one, so the refactor itself does not destroy anything. The steps below handle the parts `moved` blocks cannot cover.

## Before you start

- Terraform >= 1.10, AWS CLI v2 (the providers call `aws eks get-token`), `kubectl`.
- Work through **dev first**, then repeat for prod.
- Plan for the node group to be replaced (see step 5). Workloads are rescheduled onto new nodes once.

## 1. Back up state

```bash
cd envs/aws/dev
terraform state pull > ~/argocd-dev-state-backup-$(date +%Y%m%d).json
```

Keep this file somewhere safe and **out of git**; it contains secrets.

## 2. Create the state bucket and move state into it

```bash
cd ../../../bootstrap/aws
cp terraform.tfvars.example terraform.tfvars   # set a globally unique bucket_name
terraform init
terraform apply

cd ../../envs/aws/dev
cp backend.hcl.example backend.hcl             # set bucket to the output above
terraform init -migrate-state -upgrade -backend-config=backend.hcl
```

Answer `yes` when Terraform asks to copy the existing state to S3. `-upgrade` pulls the new major provider versions; their state upgrades run automatically on the next plan (the Helm provider prints `Successfully migrated state from SDKv2 to Plugin Framework`).

## 3. Pin the existing cluster's shape

The new defaults are for new clusters. For an existing one, edit `envs/aws/dev/main.tf` (or `envs/aws/prod/main.tf`) for this migration so nothing gets rebuilt:

```hcl
module "eks" {
  # ...
  kubernetes_version   = "1.32"                          # upgrade later, one step at a time (step 8)
  support_type         = "EXTENDED"                      # 1.32 is past standard support; switch back in step 8
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]  # prod: 10.10.0.0/24, 10.10.1.0/24
  private_subnet_cidrs = ["10.0.2.0/24", "10.0.3.0/24"]  # prod: 10.10.2.0/24, 10.10.3.0/24
  single_nat_gateway   = true                            # the old module had one NAT gateway
  # ...
}
```

Subnet CIDRs cannot be changed in place. Growing the private subnets (recommended, because the VPC CNI gives every pod a VPC IP) means a new VPC and cluster; see "Moving to the new network layout" at the end.

Then create `terraform.tfvars`:

```hcl
admin_cidrs = ["203.0.113.10/32"]   # your egress IP(s)

# Migration aids, only for clusters built by the old module:
legacy_node_cni_policy              = true
legacy_control_plane_public_subnets = true
```

- `legacy_node_cni_policy` keeps `AmazonEKS_CNI_Policy` on the node role while the VPC CNI switches to its IRSA role, so pod networking keeps working during the switch.
- `legacy_control_plane_public_subnets` keeps the control plane's subnet list exactly as before (public + private). Leave it `true` for the life of a migrated cluster unless a plan with it set to `false` shows an in-place update rather than a replacement.

## 4. Import objects that already exist

Two objects existed before but were not managed by Terraform:

```bash
# Created by EKS when logging was turned on
terraform import 'module.eks.aws_cloudwatch_log_group.cluster' /aws/eks/argocd-dev/cluster

# Created by Helm (create_namespace = true)
terraform import 'module.argocd.kubernetes_namespace_v1.argocd' argocd
```

Use `argocd-prod` for prod.

## 5. Plan and review carefully

```bash
terraform plan -out=tfplan
```

**Expected:**

- Many `(moved from module.eks_argocd...)` notes.
- In-place updates to `aws_eks_cluster.this`: authentication mode, encryption config, log types, public access CIDRs, upgrade policy.
- `aws_eks_node_group.this` **replaced**: it now uses a launch template and a name prefix. `create_before_destroy` brings the new group up before the old one drains.
- The VPC CNI add-on is updated in place with the IRSA role and network policy enabled.
- `AmazonEC2ContainerRegistryReadOnly` attachment destroyed, `AmazonEC2ContainerRegistryPullOnly` created.
- New: KMS key, OIDC provider, VPC CNI role, flow logs, launch template, default SG lockdown, access entries.
- `helm_release.argocd` updated in place to chart 10.18.0.

**Stop and investigate if you see:**

- `aws_eks_cluster.this must be replaced`
- `aws_vpc.this` or any `aws_subnet` being replaced
- `aws_kms_key` being destroyed

## 6. Apply

```bash
terraform apply tfplan
```

Enabling secrets encryption on an existing cluster re-encrypts all Secrets and **cannot be undone**. The apply typically takes 20–40 minutes, mostly the node group roll.

Check the cluster afterwards:

```bash
aws eks update-kubeconfig --region eu-west-1 --name argocd-dev
kubectl get nodes
kubectl -n kube-system get ds aws-node -o jsonpath='{.spec.template.spec.serviceAccountName}{"\n"}'
kubectl -n kube-system get sa aws-node -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}'
kubectl -n argocd get pods
```

The last two should show the `argocd-dev-vpc-cni` role and healthy Argo CD pods.

## 7. Drop the CNI policy from the node role

Set `legacy_node_cni_policy = false` in `terraform.tfvars`, then:

```bash
terraform apply
```

The only change should be the destruction of `aws_iam_role_policy_attachment.node_cni_legacy[0]`. Start a test pod afterwards to confirm it gets an IP.

## 8. Upgrade Kubernetes 1.32 → 1.35

EKS moves one minor version at a time. For each step:

1. Check for removed APIs, for example with `kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis` or a tool such as `pluto`/`kubent`.
2. Set `kubernetes_version` to the next minor (`1.33`, then `1.34`, then `1.35`).
3. `terraform apply`. The control plane upgrades first. The node group (whose `version` follows the cluster) and the add-ons (default version for the new release) follow in the same apply.

Once the cluster is on a version that is still in standard support (1.35 or later; 1.34 leaves standard support on 2026-12-02), remove the `support_type = "EXTENDED"` line so the default `STANDARD` applies. With `STANDARD`, AWS upgrades the cluster automatically when standard support ends, instead of billing extended support.

## 9. Sample app

Terraform now creates the `sample-apps` AppProject and the `nginx-app` Application through the `argocd-apps` chart (`helm_release.bootstrap`). It takes ownership of an existing `nginx-app` Application created earlier with `kubectl`, then points it at `argocd/app/overlays/aws` in the `nginx` namespace. Argo CD creates the new resources there and prunes the old ones in `default`. The nginx Service gets a **new load balancer hostname**.

Nothing to run by hand. Check with `kubectl -n argocd get applications`.

## 10. Clean up

- After **every** environment has been applied once with this version, delete `envs/aws/dev/moved.tf` and `envs/aws/prod/moved.tf`.
- Delete the local `terraform.tfstate*` files left in `envs/aws/dev/` and `envs/aws/prod/` once the S3 state is confirmed (`terraform state list` works).
- Change the Argo CD admin password, then delete `argocd-initial-admin-secret`.

## Moving to the new network layout

The new defaults use `/19` private subnets (8,190 IPs each) and, in prod, three AZs with a NAT gateway per AZ. Subnets cannot be resized, so getting there means a blue/green move:

1. Copy `envs/aws/dev/` to a new root (for example `envs/aws/dev-v2/`) with a new `cluster_name`, a non-overlapping `vpc_cidr`, the default subnet lists, a new backend `key`, and no `moved.tf`.
2. Apply it; Terraform installs Argo CD and the bootstrap Application.
3. Shift traffic/DNS to the new cluster's load balancers.
4. Destroy the old root.

## Rolling back

- Argo CD: `atomic = true` rolls back a failed chart upgrade automatically. To go back on purpose, set `chart_version = "10.9.0"` and apply.
- State: restore with `terraform state push ~/argocd-dev-state-backup-YYYYMMDD.json`. S3 versioning also keeps earlier state objects.
- Secrets encryption and the `API` authentication mode cannot be reverted. Every other cluster setting can be changed back.
