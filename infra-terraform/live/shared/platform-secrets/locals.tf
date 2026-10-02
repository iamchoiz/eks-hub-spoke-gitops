locals {
  argocd_deploy_key_secret_name = "${var.resource_prefix}/${var.argocd_deploy_key_secret_path}"
  hub_platform_secret_name      = "${var.resource_prefix}/${var.hub_platform_secret_path}"

  hub_platform_secret_string = jsonencode({
    for k in var.hub_platform_secret_keys : k => "PLACEHOLDER"
  })
}
