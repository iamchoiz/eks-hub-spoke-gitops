locals {
  repositories = {
    for svc in var.service_name : "${var.resource_prefix}/${svc}" => {
      lifecycle_policy = jsonencode({
        rules = [{
          rulePriority = 1
          description  = "untagged 이미지 ${var.untagged_expire_days}일 후 삭제"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = var.untagged_expire_days
          }
          action = { type = "expire" }
        }]
      })
    }
  }
}
