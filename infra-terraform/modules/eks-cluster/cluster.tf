resource "aws_iam_role" "cluster" {
  name               = var.cluster_role_name
  assume_role_policy = var.cluster_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = var.cluster_role_policy_arn
}

resource "aws_cloudwatch_log_group" "cluster" {
  count = var.cluster_log_group_count

  name              = var.cluster_log_group_name
  retention_in_days = var.log_retention_days
}

moved {
  from = aws_cloudwatch_log_group.cluster
  to   = aws_cloudwatch_log_group.cluster[0]
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode                         = var.cluster_authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  vpc_config {
    subnet_ids              = var.controlplane_subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  enabled_cluster_log_types = var.cluster_log_types

  upgrade_policy {
    support_type = var.cluster_upgrade_support_type
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]

  timeouts {
    create = var.cluster_create_timeout
    delete = var.cluster_delete_timeout
  }
}

resource "aws_ec2_tag" "cluster_sg_karpenter" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = var.karpenter_discovery_tag_key
  value       = var.karpenter_discovery_tag_value
}

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
}

resource "aws_eks_access_policy_association" "this" {
  for_each = var.access_entries

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.scope_type
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.this]
}
