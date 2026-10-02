output "alb_role_arn" {
  value = aws_iam_role.alb.arn
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}

output "thanos_role_arns" {
  value = aws_iam_role.thanos[*].arn
}

output "keda_role_arns" {
  value = aws_iam_role.keda_operator[*].arn
}
