# EKS Module

Provisions the EKS control plane, OIDC provider (IRSA), a Graviton managed node
group, EKS access entries, and pinned managed add-ons. All-public subnet design
(see [ADR-0001](../../../docs/adr/0001-public-subnets.md)).

## kubectl access

After `terraform apply`, configure kubectl with the command from the
`kubeconfig_command` output:

```bash
aws eks update-kubeconfig --name petclinic-dev --region eu-central-1
kubectl get nodes
```

The deploying principal is granted cluster-admin through an **EKS access entry**
(authentication mode `API_AND_CONFIG_MAP`). The implicit creator bootstrap
(`bootstrap_cluster_creator_admin_permissions`) is **disabled** so that all
admin access is managed explicitly and reproducibly via access entries. Pass
principals through `cluster_admin_principal_arns`; the environment root module
wires in the current caller automatically, resolved to its underlying IAM
role/user ARN via `aws_iam_session_context` (access entries reject raw
assumed-role session ARNs).

> Because the creator bootstrap is off, `cluster_admin_principal_arns` must be
> non-empty or no one will have cluster access.

### Adding additional users / roles

Grant another IAM user or role cluster access by adding its ARN to
`cluster_admin_principal_arns` in the environment `terraform.tfvars`, then
`plan`/`apply`:

```hcl
cluster_admin_principal_arns = [
  "arn:aws:iam::<account>:user/AdminChuck",
  "arn:aws:iam::<account>:role/platform-oncall",
]
```

This creates an `aws_eks_access_entry` + `aws_eks_access_policy_association`
(scope `cluster`, policy `AmazonEKSClusterAdminPolicy`) per principal. For
narrower access, change the policy to `AmazonEKSAdminViewPolicy` or a namespaced
scope. The legacy `aws-auth` ConfigMap also still works because the cluster uses
`API_AND_CONFIG_MAP`.

## Managed add-ons

CoreDNS, kube-proxy, VPC CNI, and the AWS EBS CSI Driver are managed as
`aws_eks_addon` resources with **pinned** versions and `OVERWRITE` conflict
resolution. The EBS CSI Driver uses a dedicated IRSA role
(`petclinic-{env}-ebs-csi-role`, `AmazonEBSCSIDriverPolicy`) and backs the
PersistentVolumes used by Prometheus/Grafana/Loki.

### Upgrading an add-on version

1. List compatible versions for the target Kubernetes version:

   ```bash
   aws eks describe-addon-versions \
     --kubernetes-version 1.37 \
     --addon-name coredns \
     --query 'addons[0].addonVersions[].addonVersion'
   ```

2. Bump the matching `addon_version_*` variable default (or override in the
   environment).
3. `terraform plan -out plan.out` then `terraform apply plan.out`.

Upgrade add-ons deliberately and one minor version at a time alongside the
cluster `cluster_version`.
