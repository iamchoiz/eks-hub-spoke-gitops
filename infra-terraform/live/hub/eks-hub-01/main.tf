data "aws_ssm_parameter" "vpc" {
  name = local.vpc_ssm_param
}

module "eks" {
  source = "git::https://github.com/your-org/eks-hub-spoke-gitops.git//infra-terraform/modules/eks-cluster?ref=main"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  controlplane_subnet_ids = local.vpc["controlplane-subnet-ids"]
  node_subnet_ids         = local.vpc["node-subnet-ids"]

  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access       = var.endpoint_public_access

  access_entries = local.access_entries

  cluster_role_name                           = local.cluster_role_name
  cluster_role_policy_arn                     = local.cluster_role_policy_arn
  cluster_assume_role_policy                  = local.service_assume_role_policy["cluster"]
  cluster_authentication_mode                 = var.cluster_authentication_mode
  bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  cluster_upgrade_support_type                = var.cluster_upgrade_support_type
  cluster_create_timeout                      = var.cluster_create_timeout
  cluster_delete_timeout                      = var.cluster_delete_timeout

  cluster_log_types       = var.cluster_log_types
  cluster_log_group_count = local.cluster_log_group_count
  cluster_log_group_name  = local.cluster_log_group_name
  log_retention_days      = var.log_retention_days

  karpenter_discovery_tag_key   = var.karpenter_discovery_tag_key
  karpenter_discovery_tag_value = local.cluster_name

  node_role_name          = local.node_role_name
  node_assume_role_policy = local.service_assume_role_policy["node"]
  node_role_policy_arns   = local.node_role_policy_arns

  system_node_group_name    = var.system_node_group_name
  system_ami_type           = var.system_ami_type
  system_kubernetes_version = var.system_kubernetes_version
  system_release_version    = var.system_release_version
  system_instance_types     = var.system_instance_types
  system_capacity_type      = var.system_capacity_type
  system_scaling            = var.system_scaling
  system_max_unavailable    = var.system_max_unavailable
  system_update_strategy    = var.system_update_strategy
  system_taint              = var.system_taint
  system_labels             = var.system_labels

  addon_names                       = var.addon_names
  addon_versions                    = var.addon_versions
  addon_resolve_conflicts_on_create = var.addon_resolve_conflicts
  addon_resolve_conflicts_on_update = var.addon_resolve_conflicts
  ebs_csi_configuration_values      = local.ebs_csi_configuration_values

  pod_identity_assume_role_policy = local.service_assume_role_policy["pod_identity"]
  ebs_csi_role_name               = local.ebs_csi_role_name
  ebs_csi_role_policy_arn         = local.ebs_csi_role_policy_arn
  ebs_csi_namespace               = var.ebs_csi_namespace
  ebs_csi_service_account         = var.ebs_csi_service_account

  allow_effect           = var.allow_effect
  service_principal_type = var.service_principal_type
  any_resource           = var.any_resource

  karpenter_node_role_name          = local.karpenter_node_role_name
  karpenter_node_access_entry_type  = var.karpenter_node_access_entry_type
  karpenter_queue_name              = local.karpenter_queue_name
  karpenter_queue_retention_seconds = var.karpenter_queue_retention_seconds
  karpenter_queue_sse_enabled       = var.karpenter_queue_sse_enabled
  karpenter_queue_policy_sid        = var.karpenter_queue_policy_sid
  karpenter_queue_policy_actions    = var.karpenter_queue_policy_actions
  karpenter_queue_policy_principals = var.karpenter_queue_policy_principals
  karpenter_event_rules             = local.karpenter_event_rules

  karpenter_controller_role_name   = local.karpenter_controller_role_name
  karpenter_controller_policy_name = var.karpenter_controller_policy_name
  karpenter_namespace              = var.karpenter_namespace
  karpenter_service_account        = var.karpenter_service_account

  karpenter_compute_sid              = var.karpenter_compute_sid
  karpenter_compute_actions          = var.karpenter_compute_actions
  karpenter_pricing_sid              = var.karpenter_pricing_sid
  karpenter_pricing_actions          = var.karpenter_pricing_actions
  karpenter_interruption_sid         = var.karpenter_interruption_sid
  karpenter_interruption_actions     = var.karpenter_interruption_actions
  karpenter_pass_node_role_sid       = var.karpenter_pass_node_role_sid
  karpenter_pass_node_role_actions   = var.karpenter_pass_node_role_actions
  karpenter_instance_profile_sid     = var.karpenter_instance_profile_sid
  karpenter_instance_profile_actions = var.karpenter_instance_profile_actions
  karpenter_eks_sid                  = var.karpenter_eks_sid
  karpenter_eks_actions              = var.karpenter_eks_actions
  karpenter_ssm_sid                  = var.karpenter_ssm_sid
  karpenter_ssm_actions              = var.karpenter_ssm_actions
  karpenter_ssm_resources            = local.karpenter_ssm_resources
}
