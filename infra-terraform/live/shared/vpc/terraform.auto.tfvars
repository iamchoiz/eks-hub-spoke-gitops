region          = "ap-northeast-2"
resource_prefix = "demo"
account_id      = "111111111111"

vpc_name_base                        = "eks"
vpc_cidr                             = "10.20.0.0/16"
azs                                  = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
public_subnet_cidrs                  = ["10.20.0.0/24", "10.20.1.0/24", "10.20.2.0/24"]
controlplane_subnet_cidrs            = ["10.20.3.0/28", "10.20.3.16/28", "10.20.3.32/28"]
node_subnet_cidrs                    = ["10.20.32.0/19", "10.20.64.0/19", "10.20.96.0/19"]
pod_secondary_cidr                   = "100.64.0.0/16"
pod_subnet_cidrs                     = ["100.64.0.0/18", "100.64.64.0/18", "100.64.128.0/18"]
nat_per_az                           = false
interface_endpoints                  = []
ssm_namespace                        = "vpc"
default_route_cidr                   = "0.0.0.0/0"
endpoints_security_group_description = "Interface VPC endpoints - allow HTTPS from VPC"
endpoints_ingress_port               = 443
endpoints_ingress_protocol           = "tcp"
endpoints_ingress_description        = "HTTPS from VPC"
ssm_param_type                       = "String"

default_tags = {
  Project    = "demo"
  Env        = "shared"
  Owner      = "admin"
  ManagedBy  = "terraform"
  CostCenter = "platform"
}
