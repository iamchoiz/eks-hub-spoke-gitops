data "aws_iam_policy_document" "spoke_trust" {
  statement {
    effect  = var.allow_effect
    actions = var.spoke_trust_actions

    principals {
      type        = var.aws_principal_type
      identifiers = [var.hub_management_role_arn]
    }
  }
}

resource "aws_iam_role" "argocd_spoke" {
  name               = var.spoke_role_name
  assume_role_policy = data.aws_iam_policy_document.spoke_trust.json
}

resource "aws_eks_access_entry" "argocd_spoke" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.argocd_spoke.arn
}

resource "aws_eks_access_policy_association" "argocd_spoke" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.argocd_spoke.arn
  policy_arn    = var.access_policy_arn

  access_scope {
    type = var.access_scope_type
  }

  depends_on = [aws_eks_access_entry.argocd_spoke]
}

resource "aws_vpc_security_group_ingress_rule" "hub_to_spoke_api" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = var.hub_security_group_id
  ip_protocol                  = var.api_ingress_protocol
  from_port                    = var.api_ingress_port
  to_port                      = var.api_ingress_port
  description                  = var.api_ingress_description
}
