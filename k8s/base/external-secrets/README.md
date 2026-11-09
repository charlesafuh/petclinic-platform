# External Secrets Operator (E-7)

**Last Updated:** 2026-11-05

**Purpose:** Install the External Secrets Operator and define the resources that
sync secrets from AWS Secrets Manager into Kubernetes Secrets for the application.

Covers PETPLAT-34 (install ESO), PETPLAT-35 (RDS credentials ExternalSecret),
PETPLAT-36 (OpenAI API key ExternalSecret). The ESO IRSA role (PETPLAT-37) lives
in `terraform/modules/eks/eso.tf`; the non-RDS secrets it reads are created by
`terraform/modules/secrets/` (PETPLAT-33).

## Contents

| File | Resource | Purpose |
|------|----------|---------|
| `namespace.yaml` | Namespace `external-secrets` | Operator namespace |
| `serviceaccount.yaml` | ServiceAccount `external-secrets-sa` | IRSA identity for AWS access |
| `cluster-secret-store.yaml` | ClusterSecretStore `aws-secrets-manager` | AWS Secrets Manager provider |
| `rds-credentials.yaml` | ExternalSecret `rds-credentials` | RDS username/password (PETPLAT-35) |
| `openai-api-key.yaml` | ExternalSecret `openai-api-key` | GenAI `OPENAI_API_KEY` (PETPLAT-36) |

## How it works

```
AWS Secrets Manager                 EKS (external-secrets ns)        App namespace (petclinic-{env})
  petclinic/{env}/rds-credentials ──▶ ESO controller ──reads via──▶  Secret: rds-credentials
  petclinic/{env}/openai-api-key  ──▶ (external-secrets-sa, IRSA)     Secret: openai-api-key
```

ESO assumes `petclinic-{env}-eso-role` through the `external-secrets-sa`
ServiceAccount (OIDC/IRSA — no static AWS keys). That role grants read-only
access scoped to `petclinic/{env}/*`. The ClusterSecretStore is cluster-scoped,
so one store serves ExternalSecrets in every namespace.

## Prerequisites

1. EKS cluster deployed with the OIDC provider and the ESO IRSA role
   (`terraform apply` in `terraform/environments/{env}` — output `eso_role_arn`).
2. Source secrets present in Secrets Manager:
   - `petclinic/{env}/rds-credentials` — created by the `rds` module.
   - `petclinic/{env}/openai-api-key` — created by the `secrets` module
     (set a value via `TF_VAR_openai_api_key`, or the ExternalSecret stays
     `SecretSyncedError` until a version exists).
3. `kubectl` pointed at the cluster:
   `aws eks update-kubeconfig --name petclinic-{env} --region eu-central-1`

## Install (kubectl apply — CRDs + controller)

ESO is pinned for reproducibility (never `latest`). Check for newer releases at
https://github.com/external-secrets/external-secrets/releases and bump `ESO_VERSION`.

```bash
# 1. Install CRDs + controller from the upstream release bundle (installs into
#    the external-secrets namespace, which it creates).
ESO_VERSION=v0.10.5
kubectl apply -f "https://github.com/external-secrets/external-secrets/releases/download/${ESO_VERSION}/external-secrets.yaml"

# 2. Wait for the controller and webhook to become ready.
kubectl -n external-secrets rollout status deploy/external-secrets
kubectl -n external-secrets rollout status deploy/external-secrets-webhook

# 3. Create the IRSA-annotated ServiceAccount. Set the role ARN first:
ESO_ROLE_ARN=$(terraform -chdir=terraform/environments/{env} output -raw eso_role_arn)
sed "s|REPLACE_WITH_ESO_ROLE_ARN|${ESO_ROLE_ARN}|" k8s/base/external-secrets/serviceaccount.yaml | kubectl apply -f -

# 4. Create the ClusterSecretStore (cluster-scoped; applied once per cluster).
kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml

# 5. Create the ExternalSecrets in the application namespace.
kubectl apply -f k8s/base/external-secrets/rds-credentials.yaml
kubectl apply -f k8s/base/external-secrets/openai-api-key.yaml
```

> In the GitOps flow these manifests are reconciled by ArgoCD rather than applied
> by hand; the `REPLACE_WITH_ESO_ROLE_ARN` placeholder and the `dev` namespace /
> `petclinic/dev/...` remoteRef keys are patched per environment by the overlay.

## Verify

```bash
# Store should report Valid / Ready.
kubectl get clustersecretstore aws-secrets-manager

# ExternalSecrets should report SecretSynced.
kubectl -n petclinic-{env} get externalsecret

# The synced Kubernetes Secrets should exist.
kubectl -n petclinic-{env} get secret rds-credentials openai-api-key
```

## Adding a new secret

1. Store the value in Secrets Manager under `petclinic/{env}/<name>` — for a
   Terraform-managed secret add it to `terraform/modules/secrets/` and pass the
   value as a sensitive variable (never hardcode it).
2. Confirm the secret name falls under `petclinic/{env}/*` so the existing ESO
   IAM policy already permits reading it (no IAM change needed).
3. Add an `ExternalSecret` manifest here referencing
   `secretStoreRef: aws-secrets-manager (ClusterSecretStore)` and the new
   `remoteRef.key`. Use `remoteRef.property` to pull a field out of a JSON secret.
4. Apply it and confirm `SecretSynced`.
