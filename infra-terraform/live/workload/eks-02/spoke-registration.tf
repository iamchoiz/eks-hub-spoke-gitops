data "aws_ssm_parameter" "hub_eks" {
  name = local.hub_eks_ssm_param
}

module "spoke_registration" {
  source = "git::https://github.com/your-org/eks-hub-spoke-gitops.git//infra-terraform/modules/spoke-registration?ref=main"

  cluster_name              = module.eks.cluster_name
  cluster_security_group_id = module.eks.cluster_security_group_id

  hub_management_role_arn = local.hub_management_role_arn
  hub_security_group_id   = local.hub_cluster_sg_id

  allow_effect        = var.allow_effect
  aws_principal_type  = var.aws_principal_type
  spoke_trust_actions = var.spoke_trust_actions

  spoke_role_name   = local.spoke_role_name
  access_policy_arn = var.spoke_access_policy_arn
  access_scope_type = var.spoke_access_scope_type

  api_ingress_protocol    = var.sg_protocol
  api_ingress_port        = var.api_ingress_port
  api_ingress_description = var.api_ingress_description
}

resource "aws_secretsmanager_secret" "spoke" {
  name                    = local.spoke_secret_name
  recovery_window_in_days = var.spoke_secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "spoke" {
  secret_id     = aws_secretsmanager_secret.spoke.id
  secret_string = local.spoke_secret_string
}
