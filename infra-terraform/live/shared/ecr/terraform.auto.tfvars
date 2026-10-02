region          = "ap-northeast-2"
resource_prefix = "demo"
account_id      = "111111111111"

service_name         = ["sample-app"]
image_tag_mutability = "IMMUTABLE"
scan_on_push         = true
untagged_expire_days = 7

default_tags = {
  Project    = "demo"
  Env        = "shared"
  Owner      = "admin"
  ManagedBy  = "terraform"
  CostCenter = "platform"
}
