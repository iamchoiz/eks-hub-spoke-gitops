region          = "ap-northeast-2"
account_id      = "111111111111"
resource_prefix = "demo"
default_tags = {
  Project    = "demo"
  Env        = "shared"
  Owner      = "admin"
  ManagedBy  = "terraform"
  CostCenter = "platform"
}
buckets = {
  thanos = "thanos-metrics"
  loki   = "loki-logs"
}
sse_algorithm             = "AES256"
abort_incomplete_mpu_days = 7
ssm_namespace             = "observability"
block_public_access       = true
bucket_key_enabled        = true
abort_mpu_rule_id         = "abort-incomplete-mpu"
policy_name_suffix        = "s3-rw"
bucket_list_actions       = ["s3:ListBucket"]
bucket_object_actions     = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
abort_mpu_rule_status     = "Enabled"
ssm_param_type            = "String"
