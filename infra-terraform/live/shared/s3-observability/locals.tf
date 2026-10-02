locals {
  bucket_names = { for k, suffix in var.buckets : k => "${var.resource_prefix}-${suffix}" }

  ssm_param_name = "/${var.resource_prefix}/${var.ssm_namespace}"

  policy_names = { for k, _ in var.buckets : k => "${var.resource_prefix}-${k}-${var.policy_name_suffix}" }
}
