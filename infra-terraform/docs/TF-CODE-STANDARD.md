# Terraform 코드 구조 표준

> 2026-10-01 확립. **전 스택·전 모듈 적용 완료.**
> live: `bootstrap`, `shared/{vpc,dns,ecr,platform-secrets,s3-observability}`, `hub/eks-hub-01`, `workload/eks-02`
> modules: `vpc`, `ecr`, `eks-cluster`, `eks-addons-iam`, `spoke-registration`

## 핵심 원칙 — 모듈은 받아서 꽂기만 한다

값은 **live 에서만** 정한다. 모듈은 아무것도 조회하지 않고, 아무 값도 스스로 정하지 않고, 아무것도 조립하지 않는다.

```
tfvars (값)  →  variables (선언)  →  locals (조립)  →  module (꽂기)
```

### 1. 값의 출처는 `terraform.auto.tfvars` 하나

- 스택마다 `terraform.auto.tfvars` **한 개**. 파일명은 전 스택 통일 (`<스택>.auto.tfvars` 금지)
- 자동 로드되므로 `terraform plan/apply` 에 `-var-file` 이 필요 없다 → CI 가 지금처럼 그냥 돈다
- 프로파일별 tfvars(`prod.tfvars` 등)로 나누지 않는다. 환경 구분은 나중에 도입한다

### 2. `variables.tf` 는 선언만

```hcl
variable "vpc_cidr" {}
```

`type`·`description`·`default` 를 쓰지 않는다. `default` 는 "모듈/스택이 값을 정하는 것"이라 원칙에 어긋나고,
값은 전부 tfvars 에 있어야 한다.

> ### ⚠️ `type` 제거의 대가 — 실제로 물렸던 사례
>
> `type` 을 지우면 **`optional(...)` 의 기본값도 같이 사라진다.** 구 `access_entries` 는
> `optional(string, "cluster")` 로 `scope_type`·`namespaces` 를 채워줬는데, `variable {}` 로
>바꾸자 그 키가 **아예 없는 상태**가 되어 `access_scope.type` 이 null 로 내려갔다.
> `validate` 는 통과하고 `terraform console` 에서 `(known after apply)` 로만 보였다.
>
> **규칙: `optional()` 에 의존하던 값은 tfvars 에 전부 명시한다.**
>
> ```hcl
> access_entries = {
>   admin = {
>     principal  = "user/admin"
>     policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
>     scope_type = "cluster"   # 구 optional 기본값 — 반드시 명시
>     namespaces = []          # 같음
>   }
> }
> ```
>
> 같은 이유로 모양이 틀린 값은 plan 이 아니라 모듈 내부에서 터진다
> (`each.value.cidr` 접근 시점) — 에러 위치가 호출부에서 모듈 안으로 밀린다.
>
> **두 번째 변종 — `for_each` 는 tuple 을 거부한다 (2026-10-01 실측).**
> 구 `type = set(string)` 이 해주던 리스트→set 변환이 사라져서, tfvars 의 `["a", "b"]` 는
> **tuple** 로 들어온다. `for_each` 는 map/set 만 받으므로 plan 에서 터진다 —
> `validate` 도 통과하고, `terraform console` 로 키를 렌더해봐도 못 잡는다 (tuple 순회 자체는 되므로).
> 실제로 물린 곳: `argocd_service_accounts`(hub)·`thanos_service_accounts`(eks-addons-iam 모듈).
>
> **규칙: 리스트 값을 `for_each` 에 쓰는 곳은 소비 지점에서 `toset()` 으로 감싼다.**
>
> ```hcl
> for_each = toset(var.argocd_service_accounts)
> ```

### 3. 조립은 `locals.tf` 에서 끝낸다

모듈에 넘기는 값은 **완성품**이어야 한다. 모듈 안에 다음이 있으면 안 된다:

| 금지 | live 에서 할 일 |
|---|---|
| `"${a}-${b}"` 문자열 조립 | 완성된 이름·태그 맵을 넘긴다 |
| `zipmap(...)` 등 자료구조 변환 | 변환 끝난 맵을 넘긴다 |
| `var.x ? a : b` 분기 | 분기 결과를 넘긴다 (예: NAT 개수는 맵의 키 개수로 표현) |
| `data "aws_region"` / `aws_caller_identity` / `aws_ssm_parameter` | live 가 조회·디코드해서 값으로 넘긴다 |
| `variable` 의 `default` | tfvars 에 쓴다 |

모듈에 남겨도 되는 것은 **그 모듈이 만든 리소스를 모으는 표현식**뿐이다.
live 가 미리 만들 수 없기 때문이다.

```hcl
route_table_ids = [for rt in aws_route_table.private : rt.id]
subnet_ids      = [for s in aws_subnet.node : s.id]
```

### 3-1. 모듈에 `enable_*` 토글을 두지 않는다

"몇 개 만들지"는 live 가 정해서 **개수**로 넘긴다. 모듈에 `var.x ? 1 : 0` 삼항이 생기지 않는다.

```hcl
# 모듈
resource "aws_iam_role" "thanos" {
  count = var.thanos_count
}

# live tfvars — 허브 1, 워크로드 1, 쓰지 않는 클러스터면 0
thanos_count = 1
keda_count   = 0
```

맵으로 표현되는 것은 **키 개수**가 곧 개수다 (`nat_gateways`, `karpenter_event_rules`).

⚠️ `count` 와 `for_each` 가 짝인 리소스는 둘을 같이 꺼야 한다 —
`thanos_count = 0` 인데 `thanos_service_accounts` 가 비어 있지 않으면
`aws_iam_role.thanos[0]` 참조에서 터진다.

### 4. 이름은 조각으로 받아 locals 에서 조립한다

완성된 이름을 tfvars 에 하드코딩하지 않는다.

```hcl
# tfvars
resource_prefix = "demo"
vpc_name_base   = "eks"

# locals.tf
vpc_name = "${var.resource_prefix}-${var.vpc_name_base}"   # = demo-eks
```

**이름 규칙: `<prefix>-<이름>-<env>`**

> ### 🔜 `<env>` 는 추후 추가한다 (확정된 계획)
>
> 지금은 `<prefix>-<이름>` 까지만 적용했다. **환경 분리를 시작하는 시점에 `env` 를 tfvars 변수로
> 추가하고 이름 꼬리에 붙인다.** 그래서 이름 조립을 전부 `locals.tf` 한 곳에 모아둔 것이다 —
> 스택당 1~2줄만 고치면 하위 리소스 이름까지 전부 따라온다
> (모듈이 `var.name` 뒤에 역할 꼬리만 붙이므로).
>
> ```hcl
> # 지금
> vpc_name = "${var.resource_prefix}-${var.vpc_name_base}"            # demo-eks
>
> # env 도입 후 — 이 한 줄만 바뀐다
> vpc_name = "${var.resource_prefix}-${var.vpc_name_base}-${var.env}" # demo-eks-dev
> ```
>
> 구체적인 순서는 아래 **환경(env) 도입 시** 항목에 있다.

예외 2개:
- **`live/bootstrap`** — state 버킷·GHA OIDC role 은 계정당 하나뿐이고 apply 도 계정당 1회뿐이라 환경 축이 없다. env 로 나누려면 계정을 나눠야 한다 (OIDC provider 는 계정당 URL 1개가 상한).
- **`karpenter.sh/discovery` 태그 값** — gitops `EC2NodeClass` 의 `subnetSelectorTerms` 가 참조하는 크로스레포 계약. prefix 만 쓰고 env 를 붙이지 않는다. 바꾸려면 gitops 를 같은 커밋에 고쳐야 한다.

### 5. `provider` 는 `versions.tf` 에

`terraform{}` · `backend{}` · `provider{}` 를 한 파일에 모은다. `main.tf` 에는 리소스·모듈 호출만 남는다.

### 6. 다른 스택이 읽는 SSM 출력은 live 가 소유한다

출력 파라미터는 모듈이 아니라 live 에 둔다 (`live/shared/vpc/ssm-outputs.tf`).
그게 **계약**이기 때문이다. 모듈이 경로(`/demo/vpc`)를 정하면 플랫폼 이름이 모듈에 박혀 재사용이 깨지고,
누가 읽는지가 live 에서 안 보인다.

### 7. 주석

`modules/vpc`, `modules/ecr`, `live/shared/*` 는 주석 없이 코드만 둔다.
예외: 코드에서 유추 불가능한 **수동 절차**는 남긴다 (`platform-secrets/argocd-deploy-key.tf` 의 키 주입 절차).

---

## Terraform 제약 — 변수로 뺄 수 없는 것 18곳

원칙 위반이 아니라 언어 제약이다. 시도하면 `terraform validate` 가 실패한다.

### `lifecycle` 메타 인수 (7곳)

```
Error: Variables not allowed
  prevent_destroy = var.zone_prevent_destroy
Variables may not be used here.
```

`lifecycle` 은 의존성 그래프 생성 **전에** 읽히므로 변수·local·삼항·함수 전부 거부된다.

| 위치 | |
|---|---|
| `live/bootstrap/main.tf` | `prevent_destroy = true` |
| `live/shared/dns/main.tf` | `prevent_destroy = true` |
| `live/shared/dns/acm.tf` | `create_before_destroy = true` |
| `live/shared/s3-observability/main.tf` | `prevent_destroy = true` |
| `live/shared/platform-secrets/hub-platform-secret.tf` | `ignore_changes = [secret_string]` |
| `modules/vpc/main.tf` | `prevent_destroy = true`, `create_before_destroy = true` |

변수로 켜고 끄려면 리소스를 `count` 로 두 벌 만들어야 하는데, 토글을 바꾸는 순간 대상이
destroy → create 된다 (Route53 존이면 존 ID 가 바뀌어 NS 위임과 external-dns 레코드가 전부 날아감).
보호 장치를 켜고 끄려다 보호 대상을 파괴하는 구조라 쓰지 않는다.

### `depends_on` (3곳)

정적 리소스 주소만 허용 — 변수면 의존성 그래프를 만들 수 없다.

### `source` (8곳)

`required_providers` 의 `source` 와 모듈 `source` 둘 다 변수 금지.
모듈 `?ref=` 도 같은 이유로 변수화 불가 — 업그레이드는 그 줄을 직접 고친다.

### `backend` 블록 전체

`bucket`·`key`·`region` 에 변수를 쓸 수 없다. 그래서 state 버킷 이름이
`live/bootstrap/terraform.auto.tfvars` 의 조각(`resource_prefix` + `state_bucket_basename`)과
**8개 스택 `versions.tf` 의 리터럴** 양쪽에 존재한다. 불가피한 중복이므로 한쪽을 바꾸면 반대쪽도 바꾼다.

---

## 해야 할 일

### ✅ state 이동 — 완료 (2026-10-01)

다른 스택이 읽는 출력(SSM 파라미터·스포크 시크릿)을 모듈 밖으로 꺼낸 데 따른 주소 이동.
5건 중 **실제 대상은 2건**이었고 실행 완료했다:

```bash
# 백업 후 실행 — vpc/hub 각각 state pull 로 백업을 떴다
cd live/shared/vpc
terraform state mv module.vpc.aws_ssm_parameter.outputs aws_ssm_parameter.outputs   # ✅

cd live/hub/eks-hub-01
terraform state mv module.eks.aws_ssm_parameter.outputs aws_ssm_parameter.outputs   # ✅
```

- **workload/eks-02 의 3건(SSM 1 + 스포크 시크릿 2)은 해당 없음** — state 가 비어 있는
  미적용 스택이라 옮길 대상이 없다. 첫 apply 때 새 주소로 바로 생성된다.
  스포크 시크릿 재생성 → ESO 끊김 우려도 같은 이유로 해당 없음.
- 사후 검증: 전 스택 plan 전수 확인 — bootstrap·shared 5개 전부 `No changes`,
  hub 는 기존 `min_size 0→1` 드리프트 1건만 남음 (이동과 무관한 수동 드리프트).
  숨은 delete+create 짝 없음 → CI delete 게이트(`.github/workflows/terraform.yml:75`) 통과 가능.
- apply 를 Actions 로만 하는 규칙의 예외(state 조작)로 로컬에서 실행했다. 이 항목이 실행 기록이다.

### plan 에서 확인할 것

**`plan` 은 내가 돌리지 못했다 (state·자격증명 없음).** 아래는 반드시 사람이 확인할 것.

| 대상 | 기대 | 근거 / 왜 봐야 하나 |
|---|---|---|
| 전체 | `0 to add, 0 to change, 0 to destroy` | 조립 결과 문자열이 기존 리터럴과 같은 것까지만 `terraform console` 로 실측했다. 주소 보존은 state 를 봐야 확정된다 |
| `for_each` 리소스 주소 | 불변 | 키를 렌더해 대조했다 — `access_entries`(admin), `node_role_policy_arns`(4), `karpenter_event_rules`(4), `argocd_service_accounts`(허브 2), `thanos_service_accounts`(허브 3·워크로드 1), `ecr repositories`(demo/sample-app) |
| `count` 리소스 주소 | `[0]` 불변 | `thanos_count=1`, `keda_count`(허브 0·워크로드 1), `cluster_log_group_count=0` — 구 토글 결과와 같다 |
| `assume_role_policy` (role 다수) | diff 없음 | `cluster`·`node` trust 는 바이트 단위 동일. **`pod_identity` trust 는 Action 배열 순서만 다르다** (구 `aws_iam_policy_document` 가 역순 출력). IAM 의미는 동일하고 프로바이더가 정책 동등성으로 억제하지만, plan 에서 확인할 가치가 있다 |
| `access_scope.type` | `"cluster"` | `optional()` 기본값 소실 사고가 있던 자리 (위 ⚠️ 참고) |

### 환경(env) 도입 시

1. 각 스택 tfvars 에 `env` 추가
2. `locals.tf` 의 이름 조립에 `-${var.env}` 추가 (스택당 1~2줄)
3. `karpenter.sh/discovery` 는 gitops `EC2NodeClass` 와 동시에 고친다
4. SSM 경로(`/demo/vpc` 등)에 env 를 넣으면 허브·워크로드의 `vpc_ssm_param` 도 같이 바꿔야 한다
5. bootstrap 은 계정을 나눠야 env 가 생긴다

---

## 검증 방법 (자격증명 없이)

```bash
# 1. 포맷
terraform fmt -check -recursive .

# 2. 모듈 단독
cd modules/vpc && terraform init -backend=false && terraform validate

# 3. live ↔ 모듈 인터페이스 — 레포 밖 임시 사본에서
#    ① backend 블록 제거 ② 모듈 source 를 로컬 경로로 치환 → init -backend=false + validate
#    push 전 모듈로 검증되고, 변수 이름·타입 불일치를 잡는다

# 4. 조립 결과 대조 — 추측 금지
terraform console <<< 'local.vpc_name'        # 기존 리터럴과 글자 단위로 같은지
```

`-var-file` 없이 돌려야 한다. `terraform.auto.tfvars` 가 자동 로드되는 게 전제다.
