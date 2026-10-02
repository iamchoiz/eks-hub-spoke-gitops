resource "aws_iam_role" "ebs_csi" {
  name               = var.ebs_csi_role_name
  assume_role_policy = var.pod_identity_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = var.ebs_csi_role_policy_arn
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = var.ebs_csi_namespace
  service_account = var.ebs_csi_service_account
  role_arn        = aws_iam_role.ebs_csi.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}
