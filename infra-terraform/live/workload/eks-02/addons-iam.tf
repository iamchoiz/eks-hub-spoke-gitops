module "addons_iam" {
  source = "git::https://github.com/your-org/eks-hub-spoke-gitops.git//infra-terraform/modules/eks-addons-iam?ref=main"

  cluster_name                    = module.eks.cluster_name
  pod_identity_assume_role_policy = local.service_assume_role_policy["pod_identity"]
  allow_effect                    = var.allow_effect
  any_resource                    = var.any_resource

  alb_role_name       = local.alb_role_name
  alb_policy_name     = var.alb_policy_name
  alb_policy_file     = var.alb_policy_file
  alb_namespace       = var.alb_namespace
  alb_service_account = var.alb_service_account

  eso_role_name         = local.eso_role_name
  eso_policy_name       = var.eso_policy_name
  eso_namespace         = var.eso_namespace
  eso_service_account   = var.eso_service_account
  eso_ssm_sid           = var.eso_ssm_sid
  eso_ssm_actions       = var.eso_ssm_actions
  eso_ssm_resources     = local.eso_ssm_resources
  eso_secrets_sid       = var.eso_secrets_sid
  eso_secrets_actions   = var.eso_secrets_actions
  eso_secrets_resources = local.eso_secrets_resources

  external_dns_role_name        = local.external_dns_role_name
  external_dns_policy_name      = var.external_dns_policy_name
  external_dns_namespace        = var.external_dns_namespace
  external_dns_service_account  = var.external_dns_service_account
  external_dns_change_sid       = var.external_dns_change_sid
  external_dns_change_actions   = var.external_dns_change_actions
  external_dns_change_resources = local.external_dns_change_resources
  external_dns_list_sid         = var.external_dns_list_sid
  external_dns_list_actions     = var.external_dns_list_actions

  thanos_count            = var.thanos_count
  thanos_role_name        = local.thanos_role_name
  thanos_policy_arn       = local.thanos_policy_arn
  thanos_namespace        = var.thanos_namespace
  thanos_service_accounts = var.thanos_service_accounts

  keda_count              = var.keda_count
  keda_role_name          = local.keda_role_name
  keda_policy_name        = var.keda_policy_name
  keda_namespace          = var.keda_namespace
  keda_service_account    = var.keda_service_account
  keda_cloudwatch_sid     = var.keda_cloudwatch_sid
  keda_cloudwatch_actions = var.keda_cloudwatch_actions
  keda_sqs_sid            = var.keda_sqs_sid
  keda_sqs_actions        = var.keda_sqs_actions
  keda_sqs_resources      = local.keda_sqs_resources

  extra_pod_identity_associations = local.extra_pod_identity_associations

}
