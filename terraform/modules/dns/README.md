# DNS Module

Route 53 + ACM for exposing the API Gateway over HTTPS, paired with the AWS Load
Balancer Controller (installed on EKS) and the Ingress manifest in
`k8s/base/ingress/`.

## What it does

- **Looks up** the existing public hosted zone for `domain_name` with a
  `data` source — it does **not** create one.
- Requests a **wildcard ACM certificate** `*.{domain_name}` (DNS validation).
- Writes the validation CNAMEs into the zone and **waits** for issuance
  (`aws_acm_certificate_validation`).
- Creates the **alias A record** `{record_name}.{domain_name}` → ALB, but only
  once the ALB exists (gated on `alb_dns_name` / `alb_zone_id`).

## Why the zone is a data source, not a resource

Route 53 automatically creates a hosted zone when you **register** a domain. If
Terraform created a *second* zone for the same domain, the registrar would still
delegate to the original zone, so the ACM DNS-validation records (written into
the Terraform-created zone) would never be visible to the public resolver and the
certificate would sit in `PENDING_VALIDATION` forever. Looking the zone up
guarantees the validation records land in the zone the domain actually delegates
to. (This intentionally deviates from PETPLAT-28's literal "hosted zone created"
wording.)

## Two-phase apply (the ALB chicken-and-egg)

The ALB is created by the Load Balancer Controller **when the Ingress is applied**,
which happens after Terraform. So the alias record is created in a second pass —
but the ALB is resolved with `data.aws_lb` (by name), **not** by passing its DNS
name as a per-run `-var`. A `-var` value is not persisted, so the next plain
`terraform apply` would drop the record; a committed `enable_alias` boolean plus a
data-source lookup avoids that.

**Phase 1 — certificate.** Apply with `enable_alias = false` (the default). This
looks up the zone and issues the wildcard certificate.

```bash
terraform apply            # enable_alias=false -> no alias record yet
CERT_ARN=$(terraform output -raw dns_certificate_arn)
```

**Phase 2 — deploy the Ingress, then the alias record.** Put `CERT_ARN` into the
Ingress `certificate-arn` annotation and apply it. The controller provisions an
ALB named by the `alb.ingress.kubernetes.io/load-balancer-name` annotation
(e.g. `petclinic-dev-alb`), which matches the module's `alb_name`. Then set
`enable_dns_alias = true` **in code** and apply:

```bash
kubectl apply -f k8s/base/ingress/            # controller provisions petclinic-dev-alb
# set enable_dns_alias = true in environments/dev (committed), then:
terraform apply                               # data.aws_lb resolves the ALB; record created
```

Because the record now derives from `data.aws_lb`, every later routine apply keeps
it in place. The app is reachable at `https://{record_name}.{domain_name}`
(HTTP→HTTPS redirect via the Ingress `ssl-redirect` annotation).

> **Before phase 1**, confirm the registrar actually delegates to this zone, or
> `aws_acm_certificate_validation` blocks for up to ~75 min:
> `dig +short NS {domain_name}` should match the `zone_name_servers` output.

## Inputs (selected)

| Variable | Default | Notes |
|----------|---------|-------|
| `domain_name` | — | apex domain with an existing public hosted zone |
| `record_name` | `""` | `petclinic-dev` (dev) / `petclinic` (prod); empty = apex |
| `certificate_domain` | `*.{domain_name}` | wildcard by default |
| `enable_alias` | `false` | flip to true in phase 2 (committed, not a `-var`) |
| `alb_name` | `""` | ALB name from the Ingress `load-balancer-name` annotation |

## Outputs

`zone_id`, `zone_name_servers`, `certificate_arn`, `certificate_domain`,
`record_fqdn`, `alias_record_created`.
