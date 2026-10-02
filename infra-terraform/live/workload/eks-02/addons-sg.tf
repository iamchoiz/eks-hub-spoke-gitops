resource "aws_vpc_security_group_ingress_rule" "hub_to_thanos_sidecar" {
  security_group_id            = module.eks.cluster_security_group_id
  referenced_security_group_id = local.hub_cluster_sg_id
  ip_protocol                  = var.sg_protocol
  from_port                    = var.thanos_sidecar_grpc_port
  to_port                      = var.thanos_sidecar_grpc_port
  description                  = var.thanos_sidecar_sg_description
}

resource "aws_vpc_security_group_ingress_rule" "policy_reporter_from_hub" {
  security_group_id            = module.eks.cluster_security_group_id
  referenced_security_group_id = local.hub_cluster_sg_id
  ip_protocol                  = var.sg_protocol
  from_port                    = var.policy_reporter_port
  to_port                      = var.policy_reporter_port
  description                  = var.policy_reporter_sg_description
}
