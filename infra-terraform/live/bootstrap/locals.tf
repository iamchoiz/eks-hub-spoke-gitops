# 이름 조립 + ARN 조립 전용. 변수에는 "이름 조각"만 두고 완성된 리소스 이름은 전부 여기서 만든다.
# variable 의 default 안에서는 다른 variable 을 참조할 수 없어서(TF 제약) 조립을 여기서 한다.
#
# 플랫폼 이름 규칙: <prefix>-<이름>-<env>
#
# ⚠️ bootstrap 은 <env> 를 붙이지 않는 유일한 예외다.
#    state 버킷과 GHA OIDC role 은 계정당 하나뿐인 부트스트랩 자원이고(OIDC provider 는 계정당
#    URL 1개가 상한) apply 도 계정당 최초 1회뿐이라 환경 축이 없다. env 로 나누려면 계정을 나눠야 한다.
locals {
  # = demo-terraform-tfstate (모든 스택 backend 의 bucket 과 동일해야 한다)
  state_bucket_name = "${var.resource_prefix}-${var.state_bucket_basename}"

  # = demo-gha-terraform (terraform.yml matrix 의 role ARN 과 동일해야 한다)
  gha_role_name = "${var.resource_prefix}-${var.gha_role_basename}"

  # 계정번호는 var.account_id 한 곳에서만 나온다
  break_glass_principal_arns = [
    for p in var.break_glass_principals : "arn:aws:iam::${var.account_id}:${p}"
  ]
}
