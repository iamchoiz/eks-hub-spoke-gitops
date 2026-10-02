locals {
  cluster_name = "${var.resource_prefix}-${var.cluster_name_base}"

  vpc_ssm_param           = "/${var.resource_prefix}/${var.vpc_ssm_namespace}"
  observability_ssm_param = "/${var.resource_prefix}/${var.observability_ssm_namespace}"
  ssm_param_name          = "/${var.resource_prefix}/${var.eks_ssm_namespace}/${local.cluster_name}"

  vpc           = jsondecode(data.aws_ssm_parameter.vpc.value)
  observability = jsondecode(data.aws_ssm_parameter.observability.value)

  loki_role_name        = "${local.cluster_name}-${var.loki_role_suffix}"
  loki_policy_arn       = local.observability[var.loki_policy_key]
  argocd_mgmt_role_name = "${local.cluster_name}-${var.argocd_mgmt_role_suffix}"

  spoke_role_arn_pattern = "arn:${var.partition}:iam::${var.account_id}:role/${var.spoke_role_name_pattern}"

  cluster_role_name              = "${local.cluster_name}-cluster"
  node_role_name                 = "${local.cluster_name}-node-system"
  karpenter_node_role_name       = "${local.cluster_name}-karpenter-node"
  karpenter_controller_role_name = "${local.cluster_name}-karpenter-controller"
  ebs_csi_role_name              = "${local.cluster_name}-ebs-csi"
  karpenter_queue_name           = "${local.cluster_name}-karpenter"
  cluster_log_group_name         = "/aws/eks/${local.cluster_name}/cluster"
  cluster_log_group_count        = length(var.cluster_log_types) > 0 ? 1 : 0

  managed_policy_prefix   = "arn:${var.partition}:iam::aws:policy"
  cluster_role_policy_arn = "${local.managed_policy_prefix}/${var.cluster_role_managed_policy}"
  ebs_csi_role_policy_arn = "${local.managed_policy_prefix}/${var.ebs_csi_managed_policy}"
  node_role_policy_arns   = toset([for p in var.node_managed_policies : "${local.managed_policy_prefix}/${p}"])

  karpenter_ssm_resources = ["arn:${var.partition}:ssm:${var.region}::parameter/aws/service/*"]

  service_assume_role_policy = {
    for k, principal in var.service_trust_principals : k => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = var.allow_effect
        Action    = var.service_trust_actions[k]
        Principal = { Service = principal }
      }]
    })
  }

  ebs_csi_configuration_values = jsonencode({
    controller = {
      tolerations = [var.ebs_csi_controller_toleration]
    }
  })

  karpenter_event_rules = {
    for k, v in var.karpenter_events : k => {
      name = "${local.cluster_name}-karpenter-${k}"
      event_pattern = jsonencode({
        source        = [v.source]
        "detail-type" = [v.detail_type]
      })
    }
  }

  access_entries = {
    for k, v in var.access_entries : k => {
      principal_arn = "arn:${var.partition}:iam::${var.account_id}:${v.principal}"
      policy_arn    = v.policy_arn
      scope_type    = v.scope_type
      namespaces    = v.scope_type == var.access_scope_namespace ? v.namespaces : null
    }
  }

  alb_role_name          = "${local.cluster_name}-aws-load-balancer-controller"
  eso_role_name          = "${local.cluster_name}-external-secrets"
  external_dns_role_name = "${local.cluster_name}-external-dns"
  thanos_role_name       = "${local.cluster_name}-thanos"
  keda_role_name         = "${local.cluster_name}-keda-operator"

  dns_ssm_param = "/${var.resource_prefix}/${var.dns_ssm_namespace}"
  dns           = jsondecode(data.aws_ssm_parameter.dns.value)

  eso_ssm_resources = ["arn:${var.partition}:ssm:${var.region}:${var.account_id}:parameter/${var.resource_prefix}/*"]
  eso_secrets_resources = [
    "arn:${var.partition}:secretsmanager:${var.region}:${var.account_id}:secret:${var.resource_prefix}/*",
    "arn:${var.partition}:secretsmanager:${var.region}:${var.account_id}:secret:${var.resource_prefix}-*",
  ]
  external_dns_change_resources = ["arn:${var.partition}:route53:::hostedzone/${local.dns[var.dns_zone_id_key]}"]
  keda_sqs_resources            = ["arn:${var.partition}:sqs:${var.region}:${var.account_id}:${var.resource_prefix}-*"]

  thanos_policy_arn = local.observability[var.thanos_policy_key]
}
