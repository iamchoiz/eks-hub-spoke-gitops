locals {
  vpc_name       = "${var.resource_prefix}-${var.vpc_name_base}"
  ssm_param_name = "/${var.resource_prefix}/${var.ssm_namespace}"

  karpenter_discovery_value = var.resource_prefix

  vpc_tags              = { Name = local.vpc_name }
  internet_gateway_tags = { Name = local.vpc_name }

  az_public = zipmap(var.azs, var.public_subnet_cidrs)
  az_cp     = zipmap(var.azs, var.controlplane_subnet_cidrs)
  az_node   = zipmap(var.azs, var.node_subnet_cidrs)
  az_pod    = zipmap(var.azs, var.pod_subnet_cidrs)

  public_subnets = {
    for az, cidr in local.az_public : az => {
      cidr = cidr
      tags = {
        Name                     = "${local.vpc_name}-public-${az}"
        "kubernetes.io/role/elb" = "1"
      }
    }
  }

  controlplane_subnets = {
    for az, cidr in local.az_cp : az => {
      cidr = cidr
      tags = { Name = "${local.vpc_name}-controlplane-${az}" }
    }
  }

  node_subnets = {
    for az, cidr in local.az_node : az => {
      cidr = cidr
      tags = {
        Name                              = "${local.vpc_name}-node-${az}"
        "kubernetes.io/role/internal-elb" = "1"
        "karpenter.sh/discovery"          = local.karpenter_discovery_value
      }
    }
  }

  pod_subnets = {
    for az, cidr in local.az_pod : az => {
      cidr = cidr
      tags = { Name = "${local.vpc_name}-pod-${az}" }
    }
  }

  nat_azs = var.nat_per_az ? var.azs : [var.azs[0]]

  nat_gateways = {
    for az in local.nat_azs : az => {
      eip_tags = { Name = "${local.vpc_name}-nat-${az}" }
      tags     = { Name = "${local.vpc_name}-${az}" }
    }
  }

  public_route_table_tags = { Name = "${local.vpc_name}-public" }

  private_route_tables = {
    for az in var.azs : az => {
      tags   = { Name = "${local.vpc_name}-private-${az}" }
      nat_az = var.nat_per_az ? az : local.nat_azs[0]
    }
  }

  s3_endpoint_service_name = "com.amazonaws.${var.region}.s3"
  s3_endpoint_tags         = { Name = "${local.vpc_name}-s3" }

  interface_endpoints = {
    for svc in var.interface_endpoints : svc => {
      service_name = "com.amazonaws.${var.region}.${svc}"
      tags         = { Name = "${local.vpc_name}-${svc}" }
    }
  }

  endpoints_security_group_name_prefix = "${local.vpc_name}-vpce-"
  endpoints_security_group_tags        = { Name = "${local.vpc_name}-vpce" }

  endpoints_ingress_cidrs = [var.vpc_cidr, var.pod_secondary_cidr]
}
