data "aws_route53_zone" "parent" {
  name         = var.parent_zone_name
  private_zone = var.parent_zone_private
}

resource "aws_route53_zone" "eks" {
  name    = var.eks_zone_name
  comment = var.eks_zone_comment

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "delegation" {
  zone_id = data.aws_route53_zone.parent.zone_id
  name    = var.eks_zone_name
  type    = var.delegation_record_type
  ttl     = var.delegation_ttl
  records = aws_route53_zone.eks.name_servers
}

resource "aws_ssm_parameter" "outputs" {
  name = local.ssm_param_name
  type = var.ssm_param_type
  value = jsonencode({
    "zone-id"          = aws_route53_zone.eks.zone_id
    "zone-name"        = var.eks_zone_name
    "acm-wildcard-arn" = aws_acm_certificate.eks_wildcard.arn
  })
}
