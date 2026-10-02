data "aws_iam_policy_document" "argocd_mgmt_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "argocd_mgmt" {
  name               = local.argocd_mgmt_role_name
  assume_role_policy = data.aws_iam_policy_document.argocd_mgmt_trust.json
}

data "aws_iam_policy_document" "argocd_mgmt" {
  statement {
    sid     = "AssumeSpokeRoles"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    resources = [
      local.spoke_role_arn_pattern
    ]
  }
}

resource "aws_iam_role_policy" "argocd_mgmt" {
  name   = var.argocd_mgmt_policy_name
  role   = aws_iam_role.argocd_mgmt.name
  policy = data.aws_iam_policy_document.argocd_mgmt.json
}

resource "aws_eks_pod_identity_association" "argocd_mgmt" {
  # toset 필수 — type 없는 variable 로는 tfvars 리스트가 tuple 로 들어와 for_each 가 거부한다 (표준 §2 함정)
  for_each = toset(var.argocd_service_accounts)

  cluster_name    = local.cluster_name
  namespace       = var.argocd_namespace
  service_account = each.value
  role_arn        = aws_iam_role.argocd_mgmt.arn

  depends_on = [module.eks]
}
