resource "aws_ssm_parameter" "outputs" {
  name = local.ssm_param_name
  type = var.ssm_param_type

  value = jsonencode({
    "name"                = module.eks.cluster_name
    "endpoint"            = module.eks.cluster_endpoint
    "ca-data"             = module.eks.cluster_ca_data
    "cluster-sg-id"       = module.eks.cluster_security_group_id
    "oidc-issuer"         = module.eks.cluster_oidc_issuer
    "karpenter-node-role" = module.eks.karpenter_node_role_name
    "karpenter-queue"     = module.eks.karpenter_queue_name
  })
}
