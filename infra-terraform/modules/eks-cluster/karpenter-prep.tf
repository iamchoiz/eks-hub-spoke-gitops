resource "aws_iam_role" "karpenter_node" {
  name               = var.karpenter_node_role_name
  assume_role_policy = var.node_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each = var.node_role_policy_arns

  role       = aws_iam_role.karpenter_node.name
  policy_arn = each.value
}

resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = var.karpenter_node_access_entry_type
}

resource "aws_sqs_queue" "karpenter" {
  name                      = var.karpenter_queue_name
  message_retention_seconds = var.karpenter_queue_retention_seconds
  sqs_managed_sse_enabled   = var.karpenter_queue_sse_enabled
}

data "aws_iam_policy_document" "karpenter_queue" {
  statement {
    sid     = var.karpenter_queue_policy_sid
    effect  = var.allow_effect
    actions = var.karpenter_queue_policy_actions

    principals {
      type        = var.service_principal_type
      identifiers = var.karpenter_queue_policy_principals
    }

    resources = [aws_sqs_queue.karpenter.arn]
  }
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id
  policy    = data.aws_iam_policy_document.karpenter_queue.json
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = var.karpenter_event_rules

  name          = each.value.name
  event_pattern = each.value.event_pattern
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = aws_cloudwatch_event_rule.karpenter

  rule = each.value.name
  arn  = aws_sqs_queue.karpenter.arn
}
