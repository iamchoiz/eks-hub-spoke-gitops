resource "aws_iam_role" "karpenter_controller" {
  name               = var.karpenter_controller_role_name
  assume_role_policy = var.pod_identity_assume_role_policy
}

data "aws_iam_policy_document" "karpenter_controller" {
  statement {
    sid       = var.karpenter_compute_sid
    effect    = var.allow_effect
    actions   = var.karpenter_compute_actions
    resources = var.any_resource
  }

  statement {
    sid       = var.karpenter_pricing_sid
    effect    = var.allow_effect
    actions   = var.karpenter_pricing_actions
    resources = var.any_resource
  }

  statement {
    sid       = var.karpenter_interruption_sid
    effect    = var.allow_effect
    actions   = var.karpenter_interruption_actions
    resources = [aws_sqs_queue.karpenter.arn]
  }

  statement {
    sid       = var.karpenter_pass_node_role_sid
    effect    = var.allow_effect
    actions   = var.karpenter_pass_node_role_actions
    resources = [aws_iam_role.karpenter_node.arn]
  }

  statement {
    sid       = var.karpenter_instance_profile_sid
    effect    = var.allow_effect
    actions   = var.karpenter_instance_profile_actions
    resources = var.any_resource
  }

  statement {
    sid       = var.karpenter_eks_sid
    effect    = var.allow_effect
    actions   = var.karpenter_eks_actions
    resources = [aws_eks_cluster.this.arn]
  }

  statement {
    sid       = var.karpenter_ssm_sid
    effect    = var.allow_effect
    actions   = var.karpenter_ssm_actions
    resources = var.karpenter_ssm_resources
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = var.karpenter_controller_policy_name
  role   = aws_iam_role.karpenter_controller.name
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.karpenter_namespace
  service_account = var.karpenter_service_account
  role_arn        = aws_iam_role.karpenter_controller.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
