# Module: secrets (PETPLAT-33)

Manages **non-RDS** application secrets in AWS Secrets Manager. RDS master
credentials are owned by the [`rds`](../rds/) module (PETPLAT-23) and are not
duplicated here.

## Secrets

| Secret | Path | Source variable | Created |
|--------|------|-----------------|---------|
| OpenAI API key | `petclinic/{env}/openai-api-key` | `openai_api_key` | Always (version only when value supplied) |
| Config Server Git username | `petclinic/{env}/config-server/git-username` | `config_server_git_username` | Only when non-empty |
| Config Server Git password | `petclinic/{env}/config-server/git-password` | `config_server_git_password` | Only when non-empty |

All encrypted with the AWS-managed `aws/secretsmanager` KMS key.

## Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project` | string | `"petclinic"` | Name prefix / secret path |
| `environment` | string | — | `dev` or `prod` |
| `openai_api_key` | string (sensitive) | `""` | OpenAI API key value |
| `config_server_git_username` | string (sensitive) | `""` | Optional private-repo Git username |
| `config_server_git_password` | string (sensitive) | `""` | Optional private-repo Git password/token |
| `secret_recovery_window_days` | number | `0` | Recovery window (0 = immediate delete; 7–30 otherwise) |
| `tags` | map(string) | `{}` | Additional tags |

## Outputs

| Output | Description |
|--------|-------------|
| `openai_secret_arn` | ARN of the OpenAI API key secret |
| `openai_secret_name` | Name of the OpenAI API key secret |
| `git_username_secret_arn` | ARN of the Git username secret (null when unmanaged) |
| `git_password_secret_arn` | ARN of the Git password secret (null when unmanaged) |

## Supplying the OpenAI key (never hardcode)

The key is a sensitive variable with no committed value. Provide it at apply time:

```bash
# Preferred: environment variable (not written to disk)
export TF_VAR_openai_api_key="sk-..."
terraform -chdir=terraform/environments/dev apply plan.out
```

Or via a **gitignored** `*.tfvars` file (`.gitignore` ignores all `*.tfvars`):

```hcl
# terraform/environments/dev/secrets.auto.tfvars  (NOT committed)
openai_api_key = "sk-..."
```

Leaving it empty creates the secret container with no version; the
[ExternalSecret](../../../k8s/base/external-secrets/openai-api-key.yaml) reports
`SecretSyncedError` until a version exists. Set the value in a later apply or via
the AWS console.

The ESO IRSA role that reads these secrets is defined in
[`terraform/modules/eks/eso.tf`](../eks/eso.tf) (PETPLAT-37), scoped to
`petclinic/{env}/*`.

## State sensitivity

`aws_secretsmanager_secret_version` stores the secret value in Terraform state.
This is unavoidable for this resource type, so the secret is only as protected as
the state. The S3 backend has `encrypt = true` and DynamoDB locking; additionally
keep the state bucket private (public access blocked), versioned, and readable
only by the deploy role. Never run `terraform plan/apply` with state written to a
local or shared location for this environment.
