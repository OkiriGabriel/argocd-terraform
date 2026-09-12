# Argo CD on Amazon EKS

Terraform that builds an Amazon EKS cluster and installs [Argo CD](https://argo-cd.readthedocs.io/) with Helm. A small nginx app in this repo is the sample GitOps workload.

## Layout

```text
modules/eks-argocd/   reusable VPC, EKS, and Argo CD install
dev/                  development stack
prod/                 production stack (separate VPC and cluster)
argocd/
  application.yaml    Argo CD Application CR
  app/                sample nginx manifests
```

Each environment uses a different cluster name and VPC CIDR so they can live in the same AWS account.

## What gets created

- VPC with 2 public and 2 private subnets, an internet gateway, and one NAT gateway
- EKS 1.32 cluster plus a managed node group
- Core add-ons: `vpc-cni`, `coredns`, `kube-proxy`
- Argo CD (Helm chart `10.9.0` / Argo CD v3.5) exposed with an internet-facing NLB

Dev uses `t3.medium` nodes (desired 2). Prod uses `t3.large` nodes (desired 3).

## Prerequisites

- Terraform >= 1.5
- AWS CLI v2, with credentials that can create VPC, IAM, EKS, and ELB resources
- `kubectl`

```bash
aws sts get-caller-identity
```

## Deploy

Pick an environment and apply from that folder. First apply usually takes 15–20 minutes.

```bash
cd dev
terraform init
terraform plan
terraform apply
```

When it finishes, point `kubectl` at the cluster:

```bash
terraform output configure_kubectl
# then run the printed command, for example:
aws eks update-kubeconfig --region eu-west-1 --name argocd-dev
```

## Open Argo CD

```bash
terraform output argocd_url
terraform output argocd_admin_password_command
```

Username is `admin`. The password command reads `argocd-initial-admin-secret`. Change that password after the first login.

The UI is HTTPS on an NLB. The default certificate is self-signed, so the browser will warn until you add your own cert.

## Deploy the sample app

After Argo CD is up and this repo is pushed:

```bash
kubectl apply -f ../argocd/application.yaml
```

Argo CD watches `argocd/app` on `main` / `HEAD` and keeps the nginx Deployment, Service, and ConfigMap in sync. Auto-sync, prune, and self-heal are on.

To see the app:

```bash
kubectl get svc nginx
```

## Tear down

```bash
cd dev   # or prod
terraform destroy
```

If destroy hangs on the NLB or node group, delete leftover LoadBalancer services first:

```bash
kubectl delete svc -n argocd argocd-server
kubectl delete svc nginx
```

Then run `terraform destroy` again.

## Optional remote state

`dev/versions.tf` and `prod/versions.tf` have a commented S3 backend. Create a bucket and DynamoDB lock table, then uncomment those blocks before `terraform init`.

## Notes

- Region defaults to `eu-west-1`. Override with `-var='aws_region=us-east-1'` if needed.
- One NAT gateway is used on purpose to keep cost down. Add a second gateway in the module if you need per-AZ HA.
- IAM roles are named after the cluster (`argocd-dev-cluster`, `argocd-prod-node`, and so on) so environments do not collide.
- Pin a newer `argo-cd` chart with `argocd_chart_version` on the module if you want to upgrade later.
