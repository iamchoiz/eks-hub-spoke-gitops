# 이미 존재하는 IAM role 을 SA 에 연결만 한다 (role 은 이 모듈이 만들지 않음).
# 용도: 기존 ECS 앱 role 재사용 등 — role 생성/정책은 원 소유자(다른 스택·콘솔) 몫.
# ⚠️ 대상 role 의 trust 에 pods.eks.amazonaws.com 이 있어야 런타임에 자격증명이 발급된다
#    (association 생성 자체는 trust 없이도 성공해서 조용히 실패하는 함정).
resource "aws_eks_pod_identity_association" "extra" {
  for_each = var.extra_pod_identity_associations

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = each.value.role_arn
}
