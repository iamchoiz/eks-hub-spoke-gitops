data "aws_ssm_parameter" "observability" {
  name = local.observability_ssm_param
}

data "aws_iam_policy_document" "loki_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "loki" {
  name               = local.loki_role_name
  assume_role_policy = data.aws_iam_policy_document.loki_trust.json
}

resource "aws_iam_role_policy_attachment" "loki_s3" {
  role       = aws_iam_role.loki.name
  policy_arn = local.loki_policy_arn
}

resource "aws_eks_pod_identity_association" "loki" {
  cluster_name    = local.cluster_name
  namespace       = var.loki_namespace
  service_account = var.loki_service_account
  role_arn        = aws_iam_role.loki.arn

  depends_on = [module.eks]
}
