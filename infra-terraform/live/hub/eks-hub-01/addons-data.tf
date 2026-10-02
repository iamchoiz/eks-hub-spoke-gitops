data "aws_ssm_parameter" "dns" {
  name = local.dns_ssm_param
}
