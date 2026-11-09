# RDS Module

MySQL 8.0 instance for the Spring Petclinic domain services, plus the master
credentials in AWS Secrets Manager.

- **Instance:** `petclinic-{env}-mysql`, `db.t4g.micro` (free-tier, Graviton/ARM), single-AZ.
- **Storage:** 20 GB `gp2`, encrypted at rest with the AWS-managed `aws/rds` KMS key.
- **Network:** DB subnet group over the VPC public subnets; reachable only via the
  RDS security group (3306 from the EKS node SG — never `0.0.0.0/0`). `publicly_accessible = false`.
- **Parameters:** `character_set_server = utf8mb4`, `collation_server = utf8mb4_unicode_ci`.
- **Credentials:** 20-char `random_password`, stored as a JSON secret
  `petclinic/{env}/rds-credentials` with `username` and `password` keys.

## Usage

```hcl
module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  backup_retention_period = 7     # 30 in prod
  skip_final_snapshot     = true  # false in prod
}
```

## Database Initialization Strategy (PETPLAT-24)

**Decision: Spring Boot auto-initialization.** This module creates one shared
`petclinic` database (via `db_name`). It does **not** create tables — schema
creation is owned by the application at startup.

### One shared database

All three database-backed services use the **same** `petclinic` database. This is
required by a cross-service foreign key: `visits.pet_id` → `pets.id`, where `pets`
is owned by customers-service. A split database-per-service design would break that
FK, so a single shared schema is intentional.

### Schemas (7 tables)

| Service | Tables | Notes |
|---------|--------|-------|
| customers-service | `types`, `owners`, `pets` | creates `pets` (referenced by visits) |
| vets-service | `vets`, `specialties`, `vet_specialties` | independent |
| visits-service | `visits` | FK `pet_id` → `pets.id` |

The SQL lives in the **application** repo (read-only) at
`src/main/resources/db/mysql/{schema.sql,data.sql}` per service.

### How it runs

Each service runs with the `mysql` Spring profile and
`spring.sql.init.mode=always`, so Spring executes its `schema.sql` (idempotent
`CREATE TABLE IF NOT EXISTS` / `CREATE DATABASE IF NOT EXISTS petclinic; USE
petclinic;`) on startup.

### Init order (enforced by deploy order)

Because `visits` has `FOREIGN KEY (pet_id) REFERENCES pets(id)`:

1. **customers-service** — creates `types`, `owners`, `pets`
2. **vets-service** — creates `vets`, `specialties`, `vet_specialties` (independent)
3. **visits-service** — creates `visits` (depends on `pets` from step 1)

Order is enforced at the Kubernetes layer (customers-service Deployment before
visits-service; see the Helm/ArgoCD epics). Spring retries the datasource on
startup, so a brief ordering race self-heals.

### Connection string (for K8s ConfigMaps)

```
jdbc:mysql://{rds-endpoint}:3306/petclinic
```

The endpoint and a ready-made `jdbc_url` are module outputs. The username and
password come from the `rds-credentials` secret via External Secrets Operator —
never hardcode them in a manifest.

## Inputs (selected)

| Variable | Default | Notes |
|----------|---------|-------|
| `instance_class` | `db.t4g.micro` | free-tier, ARM |
| `allocated_storage` / `max_allocated_storage` | `20` / `20` | autoscaling enabled only when max > allocated |
| `multi_az` | `false` | enable in real production |
| `backup_retention_period` | `7` | 30 in prod |
| `skip_final_snapshot` | `true` | false in prod |
| `secret_recovery_window_days` | `0` | immediate delete so the name is reusable after teardown; 7–30 in real prod |

## Outputs

`endpoint`, `endpoint_with_port`, `port`, `db_instance_id`, `db_instance_arn`,
`database_name`, `jdbc_url`, `secret_arn`, `secret_name`.
