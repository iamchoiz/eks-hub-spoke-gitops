resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket_name

  # lifecycle 메타 인수는 변수를 쓸 수 없다 (Terraform: "Variables may not be used here")
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = var.state_versioning_status
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.state_sse_algorithm
    }
    bucket_key_enabled = var.state_bucket_key_enabled
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = var.state_block_public_access
  block_public_policy     = var.state_block_public_access
  ignore_public_acls      = var.state_block_public_access
  restrict_public_buckets = var.state_block_public_access
}

# 옛 state 버전 무한 적체 방지
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = var.state_expire_rule_id
    status = var.state_expire_rule_status

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.state_noncurrent_expiration_days
    }
  }
}

# break-glass 를 제외한 모든 주체에게 DeleteObjectVersion Deny + TLS 강제
data "aws_iam_policy_document" "tfstate" {
  statement {
    sid    = "DenyStateHistoryDestruction"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = local.break_glass_principal_arns
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate.json

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = var.github_oidc_url
  client_id_list  = var.github_oidc_client_ids
  thumbprint_list = var.github_oidc_thumbprints
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = var.github_oidc_client_ids
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for r in var.github_repos : "repo:${r}:*"]
    }
  }
}

resource "aws_iam_role" "gha_terraform" {
  name                 = local.gha_role_name
  assume_role_policy   = data.aws_iam_policy_document.github_trust.json
  max_session_duration = var.gha_max_session_duration
}

resource "aws_iam_role_policy_attachment" "gha_terraform_admin" {
  role       = aws_iam_role.gha_terraform.name
  policy_arn = var.gha_role_policy_arn
}
