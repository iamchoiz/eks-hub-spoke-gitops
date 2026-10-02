output "cluster_name" {
  description = "클러스터 이름"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "API 서버 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "kubeconfig 갱신 명령"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
