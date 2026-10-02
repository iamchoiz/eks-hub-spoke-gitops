output "gitops_deploy_key_secret_arn" {
  description = "ArgoCD deploy key 시크릿 ARN (소비자는 이름으로 읽으므로 참고용)"
  value       = aws_secretsmanager_secret.gitops_deploy_key.arn
}

output "hub_platform_secret_arn" {
  description = "허브 플랫폼 공용 시크릿 ARN (소비자는 이름으로 읽으므로 참고용)"
  value       = aws_secretsmanager_secret.hub_platform.arn
}
