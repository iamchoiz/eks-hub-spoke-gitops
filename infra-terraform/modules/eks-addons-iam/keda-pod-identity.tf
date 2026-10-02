resource "aws_iam_role" "keda_operator" {
  count = var.keda_count

  name               = var.keda_role_name
  assume_role_policy = var.pod_identity_assume_role_policy
}

data "aws_iam_policy_document" "keda_operator" {
  count = var.keda_count

  statement {
    sid       = var.keda_cloudwatch_sid
    effect    = var.allow_effect
    actions   = var.keda_cloudwatch_actions
    resources = var.any_resource
  }

  statement {
    sid       = var.keda_sqs_sid
    effect    = var.allow_effect
    actions   = var.keda_sqs_actions
    resources = var.keda_sqs_resources
  }
}

resource "aws_iam_role_policy" "keda_operator" {
  count = var.keda_count

  name   = var.keda_policy_name
  role   = aws_iam_role.keda_operator[0].name
  policy = data.aws_iam_policy_document.keda_operator[0].json
}

resource "aws_eks_pod_identity_association" "keda_operator" {
  count = var.keda_count

  cluster_name    = var.cluster_name
  namespace       = var.keda_namespace
  service_account = var.keda_service_account
  role_arn        = aws_iam_role.keda_operator[0].arn
}
