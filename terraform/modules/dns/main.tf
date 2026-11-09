# Module: dns
#
# Route 53 + ACM for exposing the API Gateway over HTTPS. The public hosted zone
# is LOOKED UP (data source), never created: Route 53 provisions the zone when the
# domain is registered, and creating a second zone here would place the ACM
# validation records in the wrong zone, so the certificate would never validate.
#
# A wildcard ACM certificate (*.{domain}) is requested with DNS validation, the
# validation CNAMEs are written into the looked-up zone, and validation is awaited.
# The alias A record to the ALB is created only once the ALB exists (see the
# two-phase apply in README.md); it is gated on alb_dns_name/alb_zone_id.

locals {
  certificate_domain = (var.certificate_domain != null && var.certificate_domain != "") ? var.certificate_domain : "*.${var.domain_name}"
  record_fqdn        = var.record_name == "" ? var.domain_name : "${var.record_name}.${var.domain_name}"
  create_alias       = var.enable_alias
}

# Existing public hosted zone (created at domain registration).
data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

# Regional ACM certificate (same region as the ALB — eu-central-1).
resource "aws_acm_certificate" "this" {
  domain_name               = local.certificate_domain
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# One validation record per certificate domain. Keyed by domain_name, which is
# known at plan time (it comes from configuration), so for_each can build its key
# set before the certificate exists — keying by resource_record_name failed at
# plan time because that value is only computed during apply. If the apex is ever
# added as a SAN it shares a validation CNAME with the wildcard; the two distinct
# domain_name keys then write an identical record, which allow_overwrite tolerates
# (it also lets create_before_destroy re-create the record during cert rotation).
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

# Block until the certificate is issued.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# Alias A record -> ALB. The ALB is provisioned by the Load Balancer Controller
# when the Ingress is applied, with a deterministic name set via the
# alb.ingress.kubernetes.io/load-balancer-name annotation. Once it exists, flip
# enable_alias = true (a committed value, NOT a per-run -var) and this looks the
# ALB up by name and points the record at it. Because the DNS name/zone come from
# a data source rather than run-time inputs, a plain `terraform apply` no longer
# destroys the record. See README.md (phase 2).
data "aws_lb" "this" {
  count = local.create_alias ? 1 : 0
  name  = var.alb_name
}

resource "aws_route53_record" "alias" {
  count = local.create_alias ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.record_fqdn
  type    = "A"

  alias {
    name                   = data.aws_lb.this[0].dns_name
    zone_id                = data.aws_lb.this[0].zone_id
    evaluate_target_health = true
  }
}

# Optional apex alias: the bare domain (domain_name) -> the same ALB, so
# ngohnwei.com serves the app just like {record_name}.ngohnwei.com. The ACM
# certificate must also cover the apex (add it via subject_alternative_names) or
# HTTPS to the apex fails SNI. Only one environment should own the apex record.
resource "aws_route53_record" "apex_alias" {
  count = local.create_alias && var.create_apex_alias ? 1 : 0

  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = data.aws_lb.this[0].dns_name
    zone_id                = data.aws_lb.this[0].zone_id
    evaluate_target_health = true
  }
}
