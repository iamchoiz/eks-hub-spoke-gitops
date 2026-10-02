region          = "ap-northeast-2"
resource_prefix = "demo"
account_id      = "111111111111"

parent_zone_name          = "example.com."
eks_zone_name             = "eks.example.com"
delegation_ttl            = 300
ssm_namespace             = "dns"
eks_zone_comment          = "EKS platform - records managed by external-dns"
acm_validation_method     = "DNS"
acm_validation_record_ttl = 300

parent_zone_private            = false
delegation_record_type         = "NS"
ssm_param_type                 = "String"
acm_validation_allow_overwrite = true

default_tags = {
  Project    = "demo"
  Env        = "shared"
  Owner      = "admin"
  ManagedBy  = "terraform"
  CostCenter = "platform"
}
