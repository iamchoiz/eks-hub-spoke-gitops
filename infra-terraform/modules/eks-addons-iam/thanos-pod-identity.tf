resource "aws_iam_role" "thanos" {
  count = var.thanos_count

  name               = var.thanos_role_name
  assume_role_policy = var.pod_identity_assume_role_policy
}

resource "aws_iam_role_policy_attachment" "thanos_s3_rw" {
  count = var.thanos_count

  role       = aws_iam_role.thanos[0].name
  policy_arn = var.thanos_policy_arn
}

resource "aws_eks_pod_identity_association" "thanos" {
  # toset 필수 — type 없는 variable 로는 tfvars 리스트가 tuple 로 들어와 for_each 가 거부한다 (표준 §2 함정)
  for_each = toset(var.thanos_service_accounts)

  cluster_name    = var.cluster_name
  namespace       = var.thanos_namespace
  service_account = each.value
  role_arn        = aws_iam_role.thanos[0].arn
}
