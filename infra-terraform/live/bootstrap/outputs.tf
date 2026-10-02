output "state_bucket" {
  description = "Terraform state 버킷 이름"
  value       = aws_s3_bucket.tfstate.id
}

output "gha_terraform_role_arn" {
  description = "GitHub Actions 워크플로가 assume 할 role ARN (terraform.yml matrix 에 넣는다)"
  value       = aws_iam_role.gha_terraform.arn
}
