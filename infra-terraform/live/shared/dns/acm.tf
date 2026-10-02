resource "aws_acm_certificate" "eks_wildcard" {
  domain_name               = local.acm_domain_name
  subject_alternative_names = local.acm_sans
  validation_method         = var.acm_validation_method

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.eks_wildcard.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = aws_route53_zone.eks.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = var.acm_validation_record_ttl
  allow_overwrite = var.acm_validation_allow_overwrite
}

resource "aws_acm_certificate_validation" "eks_wildcard" {
  certificate_arn         = aws_acm_certificate.eks_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}
