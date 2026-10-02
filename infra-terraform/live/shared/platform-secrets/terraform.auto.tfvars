region          = "ap-northeast-2"
resource_prefix = "demo"
account_id      = "111111111111"

argocd_deploy_key_secret_path = "argocd/gitops-deploy-key"
argocd_deploy_key_description = "ArgoCD 가 gitops 레포를 읽는 read-only deploy key (SSH private). 값은 수동 put."

hub_platform_secret_path        = "platform/hub"
hub_platform_secret_description = "허브 플랫폼 공용 자격증명 (ArgoCD·Grafana GitHub SSO 등). 실제 값은 수동 put."
hub_platform_secret_keys = [
  "argocd_client_id",
  "argocd_client_secret",
  "grafana_client_id",
  "grafana_client_secret",
  "grafana_admin_user",
  "grafana_admin_password",
  "policyreporter_client_id",
  "policyreporter_client_secret",
]
secret_recovery_window_days = 7

default_tags = {
  Project   = "demo"
  Env       = "shared"
  Owner     = "admin"
  ManagedBy = "terraform"
}
