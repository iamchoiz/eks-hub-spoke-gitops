output "repository_urls" {
  description = "생성된 ECR 리포 URL (앱 CI push 대상)"
  value       = module.ecr.repository_urls
}
