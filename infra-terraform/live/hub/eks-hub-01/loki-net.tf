resource "aws_vpc_security_group_ingress_rule" "loki_gateway_from_vpc" {
  security_group_id = module.eks.cluster_security_group_id
  cidr_ipv4         = local.vpc["cidr"]
  ip_protocol       = var.loki_gateway_sg_protocol
  from_port         = var.loki_gateway_port
  to_port           = var.loki_gateway_port
  description       = var.loki_gateway_sg_description
}
