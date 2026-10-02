# ArgoCD 가 gitops(private) 레포를 읽을 deploy key 그릇. 값(개인키)은 TF 로 안 넣는다 (state 노출 방지).
# 클러스터보다 오래 사는 장수 시크릿이라 클러스터 스택이 아닌 이 스택에 둔다.
#
# 값 넣는 절차 (최초 1회):
#   ssh-keygen -t ed25519 -C "argocd-gitops-ro" -f ./argocd_gitops -N ""
#   # 공개키(argocd_gitops.pub) → gitops 레포 Settings > Deploy keys (read-only)
#   aws secretsmanager put-secret-value --secret-id demo/argocd/gitops-deploy-key \
#     --secret-string file://argocd_gitops --region ap-northeast-2
#   rm -f argocd_gitops argocd_gitops.pub

resource "aws_secretsmanager_secret" "gitops_deploy_key" {
  name                    = local.argocd_deploy_key_secret_name
  description             = var.argocd_deploy_key_description
  recovery_window_in_days = var.secret_recovery_window_days
}
