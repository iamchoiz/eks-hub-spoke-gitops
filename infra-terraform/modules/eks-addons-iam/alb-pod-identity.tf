resource "aws_iam_role" "alb" {
  name               = var.alb_role_name
  assume_role_policy = var.pod_identity_assume_role_policy
}

resource "aws_iam_role_policy" "alb" {
  name   = var.alb_policy_name
  role   = aws_iam_role.alb.name
  policy = file("${path.module}/${var.alb_policy_file}")
}

resource "aws_eks_pod_identity_association" "alb" {
  cluster_name    = var.cluster_name
  namespace       = var.alb_namespace
  service_account = var.alb_service_account
  role_arn        = aws_iam_role.alb.arn
}
