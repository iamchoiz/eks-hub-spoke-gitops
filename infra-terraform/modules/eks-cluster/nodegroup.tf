resource "aws_iam_role" "node" {
  name               = var.node_role_name
  assume_role_policy = var.node_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = var.node_role_policy_arns

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.system_node_group_name
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.node_subnet_ids

  ami_type        = var.system_ami_type
  version         = var.system_kubernetes_version
  release_version = var.system_release_version
  instance_types  = var.system_instance_types
  capacity_type   = var.system_capacity_type

  scaling_config {
    min_size     = var.system_scaling.min
    max_size     = var.system_scaling.max
    desired_size = var.system_scaling.desired
  }

  update_config {
    max_unavailable = var.system_max_unavailable
    update_strategy = var.system_update_strategy
  }

  taint {
    key    = var.system_taint.key
    value  = var.system_taint.value
    effect = var.system_taint.effect
  }

  labels = var.system_labels

  depends_on = [aws_iam_role_policy_attachment.node]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
