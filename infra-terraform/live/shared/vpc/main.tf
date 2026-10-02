module "vpc" {
  source = "git::https://github.com/your-org/eks-hub-spoke-gitops.git//infra-terraform/modules/vpc?ref=main"

  cidr               = var.vpc_cidr
  pod_secondary_cidr = var.pod_secondary_cidr

  vpc_tags              = local.vpc_tags
  internet_gateway_tags = local.internet_gateway_tags

  public_subnets       = local.public_subnets
  controlplane_subnets = local.controlplane_subnets
  node_subnets         = local.node_subnets
  pod_subnets          = local.pod_subnets

  nat_gateways = local.nat_gateways

  public_route_table_tags = local.public_route_table_tags
  private_route_tables    = local.private_route_tables
  default_route_cidr      = var.default_route_cidr

  s3_endpoint_service_name = local.s3_endpoint_service_name
  s3_endpoint_tags         = local.s3_endpoint_tags
  interface_endpoints      = local.interface_endpoints

  endpoints_security_group_name_prefix = local.endpoints_security_group_name_prefix
  endpoints_security_group_description = var.endpoints_security_group_description
  endpoints_security_group_tags        = local.endpoints_security_group_tags
  endpoints_ingress_cidrs              = local.endpoints_ingress_cidrs
  endpoints_ingress_port               = var.endpoints_ingress_port
  endpoints_ingress_protocol           = var.endpoints_ingress_protocol
  endpoints_ingress_description        = var.endpoints_ingress_description
}
