locals {
  ssm_param_name = "/${var.resource_prefix}/${var.ssm_namespace}"

  acm_domain_name = "*.${var.eks_zone_name}"
  acm_sans        = [var.eks_zone_name]
}
