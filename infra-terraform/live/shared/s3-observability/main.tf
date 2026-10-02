resource "aws_s3_bucket" "this" {
  for_each = local.bucket_names

  bucket = each.value

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.sse_algorithm
    }
    bucket_key_enabled = var.bucket_key_enabled
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    id     = var.abort_mpu_rule_id
    status = var.abort_mpu_rule_status
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_mpu_days
    }
  }
}

resource "aws_iam_policy" "bucket_rw" {
  for_each = aws_s3_bucket.this

  name = local.policy_names[each.key]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "List"
        Effect   = "Allow"
        Action   = var.bucket_list_actions
        Resource = each.value.arn
      },
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = var.bucket_object_actions
        Resource = "${each.value.arn}/*"
      }
    ]
  })
}

resource "aws_ssm_parameter" "outputs" {
  name = local.ssm_param_name
  type = var.ssm_param_type
  value = jsonencode(merge(
    { for k, b in aws_s3_bucket.this : "${k}-bucket" => b.id },
    { for k, p in aws_iam_policy.bucket_rw : "${k}-policy-arn" => p.arn },
  ))
}
