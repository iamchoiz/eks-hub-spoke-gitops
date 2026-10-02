resource "aws_ssm_parameter" "outputs" {
  name = local.ssm_param_name
  type = var.ssm_param_type

  value = jsonencode({
    "id"                      = module.vpc.vpc_id
    "cidr"                    = var.vpc_cidr
    "public-subnet-ids"       = module.vpc.public_subnet_ids
    "controlplane-subnet-ids" = module.vpc.controlplane_subnet_ids
    "node-subnet-ids"         = module.vpc.node_subnet_ids
    "pod-subnet-ids"          = module.vpc.pod_subnet_ids
  })
}
