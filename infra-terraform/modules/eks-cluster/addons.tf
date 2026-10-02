resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = var.addon_names.vpc_cni
  addon_version               = var.addon_versions.vpc_cni
  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = var.addon_names.kube_proxy
  addon_version               = var.addon_versions.kube_proxy
  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = var.addon_names.eks_pod_identity_agent
  addon_version               = var.addon_versions.eks_pod_identity_agent
  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = var.addon_names.coredns
  addon_version               = var.addon_versions.coredns
  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update

  depends_on = [aws_eks_node_group.system]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = var.addon_names.aws_ebs_csi_driver
  addon_version               = var.addon_versions.aws_ebs_csi_driver
  resolve_conflicts_on_create = var.addon_resolve_conflicts_on_create
  resolve_conflicts_on_update = var.addon_resolve_conflicts_on_update
  configuration_values        = var.ebs_csi_configuration_values

  depends_on = [
    aws_eks_node_group.system,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}
