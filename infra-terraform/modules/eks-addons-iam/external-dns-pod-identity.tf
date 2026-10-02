resource "aws_iam_role" "external_dns" {
  name               = var.external_dns_role_name
  assume_role_policy = var.pod_identity_assume_role_policy
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    sid       = var.external_dns_change_sid
    effect    = var.allow_effect
    actions   = var.external_dns_change_actions
    resources = var.external_dns_change_resources
  }

  statement {
    sid       = var.external_dns_list_sid
    effect    = var.allow_effect
    actions   = var.external_dns_list_actions
    resources = var.any_resource
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = var.external_dns_policy_name
  role   = aws_iam_role.external_dns.name
  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_eks_pod_identity_association" "external_dns" {
  cluster_name    = var.cluster_name
  namespace       = var.external_dns_namespace
  service_account = var.external_dns_service_account
  role_arn        = aws_iam_role.external_dns.arn
}
