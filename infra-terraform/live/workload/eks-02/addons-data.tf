data "aws_ssm_parameter" "dns" {
  name = local.dns_ssm_param
}

data "aws_ssm_parameter" "observability" {
  name = local.observability_ssm_param
}
