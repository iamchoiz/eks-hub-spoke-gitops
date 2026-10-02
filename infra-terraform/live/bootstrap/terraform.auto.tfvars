region          = "ap-northeast-2"
resource_prefix = "demo"
account_id      = "111111111111"
default_tags = {
  Project   = "demo"
  Env       = "shared"
  Owner     = "admin"
  ManagedBy = "terraform"
}

break_glass_principals = ["user/admin"]
github_repos = [
  "your-org/eks-hub-spoke-gitops",
  "your-org/eks-hub-spoke-gitops", # B3 ArgoCD 부트스트랩 워크플로용
]
github_oidc_url          = "https://token.actions.githubusercontent.com"
github_oidc_client_ids   = ["sts.amazonaws.com"]
github_oidc_thumbprints  = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
gha_role_basename        = "gha-terraform"
gha_role_policy_arn      = "arn:aws:iam::aws:policy/AdministratorAccess"
gha_max_session_duration = 3600

state_bucket_basename            = "terraform-tfstate"
state_versioning_status          = "Enabled"
state_bucket_key_enabled         = true
state_block_public_access        = true
state_expire_rule_id             = "expire-noncurrent-versions"
state_expire_rule_status         = "Enabled"
state_sse_algorithm              = "AES256"
state_noncurrent_expiration_days = 90

