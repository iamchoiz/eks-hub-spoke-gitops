resource "aws_iam_role" "eso" {
  name               = var.eso_role_name
  assume_role_policy = var.pod_identity_assume_role_policy
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid       = var.eso_ssm_sid
    effect    = var.allow_effect
    actions   = var.eso_ssm_actions
    resources = var.eso_ssm_resources
  }

  statement {
    sid       = var.eso_secrets_sid
    effect    = var.allow_effect
    actions   = var.eso_secrets_actions
    resources = var.eso_secrets_resources
  }
}

resource "aws_iam_role_policy" "eso" {
  name   = var.eso_policy_name
  role   = aws_iam_role.eso.name
  policy = data.aws_iam_policy_document.eso.json
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = var.eso_namespace
  service_account = var.eso_service_account
  role_arn        = aws_iam_role.eso.arn
}
