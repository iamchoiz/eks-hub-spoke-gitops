# EKS 플랫폼 구축 계획

> **목적: EKS 운영 역량 확보 (학습 1순위).** ECS 마이그레이션은 그 역량을 검증하는 수단이고,
> "가장 빠르게 ECS 를 끄는 방법" 이 아니다. 그래서 관리형 서비스와 EKS Auto Mode 를 의도적으로 배제했다.
> 운영 부담이 늘어나는 것이 비용이 아니라 목적이다.
>
> 리전 `ap-northeast-2` · prefix `demo-` · 계정 1개 · VPC 1개
> 레포: `infra-terraform` (AWS) / `eks-gitops` (클러스터 안)

---

## 1. 확정 구성

| 영역 | 결정 |
|---|---|
| 클러스터 | **2개** — `demo-hub-01` (ArgoCD·관측·시크릿) + `demo-eks-01` (워크로드). 환경(dev/qa/uat/prod)은 namespace |
| 컴퓨팅 | **Karpenter.** 관리형 노드그룹은 부트스트랩용 2~3노드만 (`system`, `CriticalAddonsOnly` taint) |
| 노드 AMI | **Bottlerocket.** 버전 핀 필수, `@latest` 금지. *전제: EDR 지원 확인* |
| ArgoCD | **hub-and-spoke, 허브 1개.** self-manage. ApplicationSet cluster generator 로 클러스터 자동 편입 |
| 네트워크 | **EKS 전용 신규 VPC 를 만든다** — 기존 ECS VPC 를 재사용하지 않는다. 허브·워크로드가 그 VPC 1개를 공유. CIDR·서브넷은 Terraform **variable 입력** (나중에 쪼개기 쉽게). EKS 엔드포인트 public+private + CIDR allowlist |
| 메트릭 | **Prometheus(워크로드) → remote_write → Thanos Receive(허브) → S3.** Grafana·Alertmanager 자체 구축 |
| 로그 | **Loki(허브, S3).** 예외: 컨트롤플레인 audit log 는 CloudWatch Logs 전용 |
| 시크릿 | **ESO.** 백엔드는 Secrets Manager 로 시작 → **Vault(허브) 로 교체** + Raft 스냅샷 백업. 반영은 `reloader` |
| IAM | **EKS Pod Identity** + **Access Entry** (aws-auth ConfigMap 안 씀) |
| Ingress | ALB Controller + Ingress. `group.name` 으로 ALB 샤딩 |
| 네트워크 정책 | VPC CNI network policy, namespace 별 **default-deny** |
| 정책 | Pod Security Admission + Kyverno. 전부 `Audit` 으로 시작해 `Enforce` 승격 |
| 오토스케일 | HPA(+metrics-server) + KEDA. request 적정화는 VPA recommender |
| 배포 | CI → ECR push → gitops 레포 커밋 → ArgoCD sync. prod 는 Argo Rollouts canary |
| 이미지 | ECR `IMMUTABLE`. **승격은 태그가 아니라 digest(`@sha256:`)** |
| 매니페스트 | Kustomize(자사 앱) + Helm(서드파티만, chart version 고정) |
| 업그레이드 | **in-place 기본** (N-1 유지, 분기 1회) + **blue/green 연 1회 리허설** |
| IaC | **Terraform.** Crossplane·ACK 미채택 (AWS 리소스 소유권 충돌) |

### 버전 전략 — 일부러 낮게 시작한다

업그레이드를 실제로 해보는 것이 학습 목표라서 **의도적으로 낮은 버전에서 출발한다.**

| 대상 | 시작 버전 | 근거 |
|---|---|---|
| **EKS** | **1.34** | standard support 중 가장 낮은 버전 (현재 standard = 1.36/1.35/1.34). **1.34 → 1.35 → 1.36 두 번**을 in-place 로 연습한다 |
| EKS 애드온 (CoreDNS·kube-proxy·VPC CNI·EBS CSI·Pod Identity Agent) | 1.34 호환 중 **최저** | `aws eks describe-addon-versions --kubernetes-version 1.34` 로 목록을 뽑아 default 보다 낮은 것을 고른다 |
| Helm 차트 (ArgoCD·Karpenter·Thanos·Grafana·Loki·Vault·Kyverno…) | 최신에서 **2~3 마이너 뒤** | 단 아래 하한선을 지킨다 |

**extended support(1.33 이하)로는 안 내려간다.** 클러스터 시간당 $0.10 → **$0.60**. 클러스터 2개면 월 약 $730 추가다. 업그레이드 한 번 더 해보려고 낼 돈이 아니다.

**1.34 시작이 학습에 유리한 이유** — 앞으로 할 두 업그레이드에 진짜 breaking change 가 있다:
- **1.35**: cgroup v1 지원 제거 (Bottlerocket 은 `failCgroupV1: false` 로 하위호환 유지), **containerd 1.x 지원 마지막 버전**, kube-proxy IPVS deprecated, `--pod-infra-container-image` 플래그 제거
- **1.36**: `gitRepo` 볼륨 영구 비활성, **`StrictIPCIDRValidation` 기본 활성** (매니페스트의 선행 0 IP·비정규 CIDR 거부), IPVS 제거, SELinux 볼륨 라벨링 GA

트리비얼한 업그레이드가 아니라 실제 대응을 해봐야 하는 구간이다.

**차트 버전 하한선 — 이 넷을 확인하고 내린다:**
1. 그 차트가 **k8s 1.34 를 지원**하는가 (너무 낮으면 CRD apiVersion 이 안 맞아 아예 안 뜬다)
2. **우리가 의존하는 기능이 있는가** — ArgoCD 는 `awsAuthConfig` + cluster generator, Kyverno 는 CEL 정책 타입(1.19 계열 필요, 구 `ClusterPolicy` 는 deprecated)
3. **Karpenter 는 EKS 버전 호환 매트릭스가 명시**되어 있다 — 반드시 확인하고 고른다
4. **노출면이 있는 컴포넌트(ArgoCD·Grafana·oauth2-proxy)는 알려진 CVE 가 없는 버전** — "낮게 시작" 학습은 Thanos·Loki 같은 내부 컴포넌트로 충분하다. 인증 경로에 있는 것은 보안 패치를 포기하지 않는다

**버전은 전부 파일에 고정한다.** `versions.tf`, 애드온 `addon_version`, Helm `Chart.yaml` 의 `version:`, EC2NodeClass 의 AMI alias. **`latest`·`*` 금지.** 업그레이드는 Phase F 에서 **한 번에 하나만** 올린다.

### 멀티계정 대비 규칙 — 지금은 계정 1개지만, 전부 계정이 갈라진다는 전제로 짠다

**계정 경계에서 부러지는 것과 그 대비:**

| 규칙 | 이유 |
|---|---|
| ⭐ **CIDR 은 조직 전체 할당표에서 꺼내 쓴다** (아래 표). VPC 를 만들 때마다 표를 갱신한다 | 계정 간 peering/TGW 에서 CIDR 중복은 **나중에 못 고친다.** 지금 유일하게 비가역인 결정 |
| state 버킷·backend 는 **계정당 1개** (`demo-terraform-tfstate` 는 111111111111 소유) | state 는 계정 안에 산다. 새 계정 = 새 버킷 + 새 bootstrap |
| state 간 참조는 SSM — cross-account 는 **role assume 로 읽는다** (ESO·TF 둘 다 지원) | `terraform_remote_state` 금지 이유가 하나 더: 계정 경계를 아예 못 넘는다 |
| CI 는 **계정마다 OIDC provider + role.** 워크플로 matrix 가 스택별 role 을 매핑 | GitHub OIDC provider 는 계정 리소스다. 중앙 role 하나로 전 계정을 만지는 구조를 만들지 않는다 |
| **플랫폼 경계 = repo** (infra-terraform ↔ eks-gitops). 다른 플랫폼 = 다른 repo. repo 안에 `live/demo/` 같은 플랫폼 이름 폴더는 두지 않는다(중복) | repo 가 이미 플랫폼 스코프다. 같은 플랫폼에 계정이 여러 개(dev/prod) 생기면 그때 `live/<계정역할>/` 도입 — 지금은 1계정이라 `live/{bootstrap,shared,hub,workload}/` 평면 |
| 리소스 이름에 전역 유일성이 필요한 것(S3 등)만 계정 구분자를 갖는다 | 그 외는 `demo-` prefix 로 충분 — 계정이 이미 경계다 |

**CIDR 할당표 (routable 10.x 공간 — 조직 전체에서 유일해야 한다):**

| 대역 | 할당 | 상태 |
|---|---|---|
| `10.0.0.0/16` | 기존 ECS VPC (`demo-main-vpc-shared`, 111111111111) | 사용 중 |
| `10.20.0.0/16` | EKS 플랫폼 VPC (`demo-eks`, 111111111111) | 사용 중 |
| `10.21.0.0/16` ~ `10.29.0.0/16` | 미래 계정/VPC 용 예약 | 예약 |
| `100.64.0.0/16` | pod secondary — **non-routable, 계정마다 재사용 가능** | 사용 중 |

### 못 박을 5가지 원칙

1. **클러스터는 소모품이다** — 이름에 시퀀스 번호(`-01`). 클러스터 안에 상태 없음, 모든 것이 Git 에, DNS 는 클러스터에 안 묶임. *예외: 허브는 소모품이 아니다 (ArgoCD·Thanos·Vault 상태를 들고 있음)*
2. **Terraform / GitOps 경계 = 수명주기** — 계정·클러스터보다 오래 사는 것은 Terraform, 워크로드 수명주기를 따르는 것은 GitOps. **`helm_release`·`kubernetes_manifest` 금지, 예외 0개**
3. **환경은 디렉토리다, 브랜치가 아니다** — `main` 하나
4. **이미지 태그는 불변** — `sha-<gitsha>` 또는 digest. `latest` 금지
5. **관측이 워크로드보다 먼저** — 로그·메트릭이 돌기 전에 어떤 서비스도 올리지 않는다

---

## 2. 어디서 관리하나

| 대상 | 레포 |
|---|---|
| VPC · 서브넷 · SG · NAT | `infra-terraform` |
| EKS 컨트롤플레인 · EKS 애드온 버전 | `infra-terraform` |
| 관리형 노드그룹 (`system`) · Karpenter 용 IAM/인스턴스 프로파일 | `infra-terraform` |
| IAM role · **Pod Identity association** · Access Entry | `infra-terraform` |
| ECR · S3 (Thanos·Loki) · Terraform state 버킷 | `infra-terraform` |
| **Karpenter NodePool · EC2NodeClass** | `eks-gitops` ← 노드는 AWS 리소스지만 **선언은 K8s API** |
| 애드온 워크로드 (ESO·ALB Controller·Kyverno·Prometheus·Thanos·Grafana·Loki·Vault…) | `eks-gitops` |
| **ArgoCD 자신** | 부트스트랩만 CI 워크플로, 이후 `eks-gitops` (self-manage) |
| Deployment · Service · Ingress · HPA · PDB · NetworkPolicy | `eks-gitops` |
| Namespace · ResourceQuota · LimitRange · PriorityClass | `eks-gitops` |
| ArgoCD 부트스트랩 워크플로 | `infra-terraform` 의 `.github/workflows/` — **Terraform 리소스가 아니다** |

### 디렉토리

```
infra-terraform/
  modules/
    vpc/  eks-cluster/  ecr/  eks-addons-iam/  spoke-registration/
  live/
    bootstrap/          # state 버킷 + OIDC (최초 1회만 로컬 백엔드)
    shared/             # vpc/  ecr/  s3-observability/  dns/
    hub/eks-hub-01/     # 클러스터 1개 = 1 state. 절대 합치지 않는다
    workload/eks-01/
  .github/workflows/    # plan/apply + ArgoCD 부트스트랩(=break-glass)

eks-gitops/            # platform=Helm, apps=Kustomize
  platform/                        # Helm — 폴더 스코프로 클러스터 구분 (overlay 아님)
    hub/argocd/         # argocd chart(Chart.yaml,values.yaml) + install-argocd.sh + root-app.yaml
    hub/                # 그 외 허브 전용: thanos, grafana, alertmanager, loki, vault
    workload/           # 워크로드 전용: keda, kyverno, node-problem-detector
    common/             # 양쪽 공통: karpenter, eso, alb-controller (values-<cluster>.yaml 로 차이)
  clusters/
    platform-appset.yaml   # cluster generator
    apps-appset.yaml       # cluster generator + git generator
  apps/<service>/{base,overlays/{dev,qa,uat,prod}}/   # Kustomize — overlay 는 여기만
```

---

### 코드 규칙 — day-1 에 지켜야 day-2 가 안 아픈 것

**모든 규칙은 "나중에 업그레이드할 때 무엇이 터지는가" 에서 나왔다.** 처음부터 이렇게 쓴다.

#### Terraform

| 규칙 | 안 지키면 나중에 |
|---|---|
| **버전을 전부 variable + tfvars 로** (`kubernetes_version`, 각 `addon_version`) | 업그레이드가 코드 수정이 된다. variable 이면 **tfvars 한 줄 + PR** 이고 plan 으로 영향 범위가 보이고 롤백이 `git revert` 다 |
| **모듈을 버전 태그로 참조** — `source = "git::…//modules/eks-cluster?ref=v1.2.0"` | 상대경로(`../../modules/…`)로 참조하면 **모듈 수정이 두 클러스터에 동시 반영**된다. 그러면 "허브 먼저 → 1주 관찰 → 워크로드"(F3)가 **원리적으로 불가능**하고 blue/green(F6)도 안 된다 |
| **state 를 잘게 쪼갠다** — `shared`(VPC·ECR·S3) 와 클러스터를 분리 | 클러스터를 지우거나 다시 만들 때 VPC 가 같이 흔들린다. F6 에서 `-01` 을 삭제할 수 있어야 한다 |
| **state 간 참조는 SSM/태그로. `terraform_remote_state` 금지** | remote_state 는 남의 state 를 직접 읽어 강결합된다. 한쪽 리팩터링이 다른 쪽 plan 을 깨뜨린다 |
| **`for_each` 를 쓰고 `count` 를 피한다** | `count` 는 인덱스 기반이라 중간 항목을 지우면 **뒤의 리소스가 전부 재생성**된다 |
| **리팩터링은 `moved` 블록으로** | `terraform state mv` 수동 작업이 남는다. 코드로 남으면 리뷰되고 재현된다 |
| **`prevent_destroy` + plan JSON 게이트** — 클러스터·VPC·노드그룹·state 버킷 | `destroy` 금지만으로는 부족하다. 리소스 블록 삭제나 `for_each` 키 변경으로 **`apply` 가 클러스터를 지운다.** CI 에서 `terraform show -json` 의 delete 액션을 검사한다 |
| **`ignore_changes` 남용 금지** | drift 를 숨기면 업그레이드 때 몰아서 터진다 |
| **provider 버전 핀 + `.terraform.lock.hcl` 커밋** | 같은 코드가 다른 결과를 낸다 |
| **하드코딩된 ARN·ID·서브넷 금지** — data source 또는 SSM | 클러스터를 다시 만들 때 전부 손으로 고친다 |

#### GitOps

| 규칙 | 안 지키면 나중에 |
|---|---|
| ⭐ **차트 버전을 `overlays/<cluster>/` 에 둔다. `base/` 에 두지 않는다** | base 에 버전이 있으면 **두 클러스터가 항상 같이 올라간다.** 허브를 카나리로 쓰는 F3 전략이 불가능해진다. overlay 에 있으면 허브만 먼저 올리는 게 파일 한 곳 수정이다 |
| **차트 버전을 파일에 고정** — `Chart.yaml` dependency `version:` 또는 Application `targetRevision`. `*`·`HEAD` 금지 | 어느 날 sync 가 저절로 새 버전을 가져와서 깨진다. 언제 무엇이 올라갔는지도 모른다 |
| **sync wave 를 처음부터 붙인다** — CRD(-2) → 컨트롤러(-1) → 그 CRD 를 쓰는 리소스(0) | 나중에 붙이면 업그레이드 때 순서가 꼬여서 "CRD 없음" 에러가 난다. 처음에는 어차피 순서가 맞아서 문제가 안 보인다 |
| **CRD 를 별도 Application 으로 분리 + `Replace=true`** | **Helm 은 upgrade 시 CRD 를 갱신하지 않는다(기본 동작).** 차트만 올리면 CRD 가 낡은 채 남아서 새 필드가 조용히 무시된다 |
| **`ServerSideApply=true`** (kube-prometheus 등 큰 CRD) | client-side apply 의 annotation 크기 제한(262144 bytes)에 걸려 sync 가 실패한다 |
| **`argocd.argoproj.io/manifest-generate-paths`** | monorepo 라서 없으면 **커밋 하나가 모든 Application 의 캐시를 무효화**한다. 서비스가 늘면 repo-server 가 죽는다 |
| **`selfHeal` 전역 on, prod `autoPrune` 은 신중** | selfHeal 이 없으면 손으로 바꾼 것이 남아 drift 가 쌓인다 |
| **ApplicationSet(cluster generator)로 등록 자동화** | 새 클러스터마다 Application 파일을 손으로 만들면 F6 blue/green 이 수작업이 된다 |
| **이미지는 digest(`@sha256:`)로 승격** | 태그를 옮기는 것은 아티팩트 동일성을 보장하지 않는다 |
| **Kustomize `openapi` 설정** | Rollout 같은 CRD 에 image transformer 가 **에러 없이 미적용**된다. 조용한 실패 |

### 자동화 목록 — 사람이 손대면 안 되는 것

| 대상 | 수단 | 언제 |
|---|---|---|
| Terraform plan/apply | GitHub Actions + OIDC | A2 |
| **차트·애드온 새 버전 감지 → PR** | **Renovate** (자체 호스팅 또는 GitHub App) | A2. **버전을 파일에 고정하는 것과 짝이다** — 고정하면 추적이 필요해지고, Renovate 가 그 PR 을 만들어준다. 그 PR 이 곧 F1·F2 업그레이드 스터디 재료 |
| 스포크 클러스터 등록 | SSM → ESO → cluster generator | C2. **`kubectl` 0** |
| namespace 통제 부착 (Quota·LimitRange·NetworkPolicy) | Kyverno `GeneratingPolicy` | C5 |
| 노드 AMI 갱신 → 교체 | Karpenter drift + disruption budget | C3 |
| 인증서 발급·갱신 | cert-manager | C4 |
| DNS 레코드 | external-dns (`upsert-only`, 전용 서브도메인) | C4 |
| 시크릿 동기화 → 파드 반영 | ESO + `reloader` | C4 / E2 |
| 이미지 태그 → gitops 커밋 | 앱 레포 CI | D2 |
| 정책 위반 리포트 | policy-reporter | E4 |

**손으로 하는 것 (전부 사람이 `admin` 로):** ① A1 state 버킷 부트스트랩(닭-달걀), ② B3 ArgoCD 최초 설치 = break-glass(로컬 helm, GitHub 비의존), ③ B4 `root-app.yaml` 최초 `kubectl apply` 1회.
> B3 를 자동화하지 않는 이유: break-glass 는 속도가 생명이라 CI 경유가 느리고 GitHub 장애에 취약하며, 그거 하나 자동화하려고 CI role 에 클러스터 ClusterAdmin 을 상시 주는 건 과하다. **CI role(demo-gha-terraform)은 클러스터 접근이 없다** — 순수 IaC(IAM API)만.

---

## 3. 할 일 순서

> ### 🖥 프레젠테이션 → **[`EKS-MIGRATION-DECK.html`](./EKS-MIGRATION-DECK.html)** — 전체 계획을 슬라이드로. `open EKS-MIGRATION-DECK.html`
> ### 📐 전체 흐름도 → **[`eks-build-order.html`](./eks-build-order.html)**
>
> 단계별 소유자(Terraform / GitHub Actions / ArgoCD / 수동)와 막히는 의존 관계를 한 화면에 그린 도식.
> 브라우저로 열면 된다: `open eks-build-order.html`
>
> 아래는 같은 내용의 상세 텍스트다.

---

### Phase A — Terraform 기반

#### A1. state 백엔드 부트스트랩 `TF`
1. `live/bootstrap/` 에 **backend 블록 없이** `main.tf` 작성 (state 를 담을 버킷을 만드는 중이라 아직 로컬 state)
2. S3 버킷 생성 — versioning **on**, SSE(SSE-S3 또는 KMS), public access block 전부 on
3. 버킷 정책: 브레이크글래스 role 을 제외한 모든 주체에게 `s3:DeleteObjectVersion` **Deny** (state 이력 파괴 방지)
4. `terraform init && terraform apply` (로컬 state 로 실행)
5. 같은 디렉토리에 `backend "s3"` 블록 추가 (`use_lockfile = true` — **Terraform ≥ 1.10 필요**, A2 버전 핀 하한) → `terraform init -migrate-state`
6. 로컬 `terraform.tfstate*` 삭제, `.gitignore` 에 `*.tfstate*`, `.terraform/` 추가

**완료:** `terraform state list` 가 S3 백엔드에서 읽힌다. 두 번째 `apply` 를 동시에 돌리면 lock 이 걸린다.

#### A2. 레포 스켈레톤 + CI `TF` `GO`
1. `TF` 디렉토리: `modules/{vpc,eks-cluster,ecr,eks-addons-iam,spoke-registration}/`, `live/{bootstrap,shared,hub,workload}/`, `.github/workflows/`
   > 2026-10-01 정정: 계획 단계의 `pod-identity/` 는 실제로 **`eks-addons-iam/`** 으로 구현됐다.
   > Pod Identity 는 전용 모듈이 아니라 두 곳에 나뉘어 있다 — 애드온용(ESO·ALB·external-dns·Thanos·KEDA)은
   > `eks-addons-iam/`, 클러스터에 묶인 것(ebs-csi·karpenter)은 `eks-cluster/`.
   > 빈 `modules/pod-identity/` 디렉토리는 같은 날 제거했다.
2. `GO` 디렉토리: `platform/{hub,workload,common}/`(Helm), `clusters/`(appset), `apps/`(Kustomize). ※ 빈 폴더는 미리 안 만든다 — 각 Phase 에서 just-in-time
3. 두 레포 README — §1 원칙 5개 + §2 소유권 표를 그대로 박는다 (나중에 "이게 왜 여기 있냐" 논쟁을 없앤다)
4. `CODEOWNERS` — `platform/` = 플랫폼팀, `apps/<svc>/` = 서비스팀
5. **GitHub Actions OIDC** 로 AWS 인증 — IAM role + trust policy(`token.actions.githubusercontent.com`). **액세스 키 안 만든다**
6. `TF` 워크플로: `fmt -check` → `validate` → `plan` → **PR 코멘트**. merge 시 `apply` (수동 승인 게이트)
7. `main` 브랜치 보호: PR 필수, plan 성공 필수, force push 금지
8. `versions.tf` — Terraform 버전과 provider 버전 **핀 고정**, `.terraform.lock.hcl` 커밋
9. **Renovate 설정** (`renovate.json`) — Terraform provider·모듈, Helm 차트, EKS 애드온 버전을 감시해서 **새 버전이 나오면 PR 을 만든다.** 자동 merge 는 끄고 PR 만 받는다 — 그 PR 이 F1·F2 의 업그레이드 스터디 재료가 된다

**완료:** PR 을 올리면 plan 이 코멘트로 달리고, merge 없이는 apply 가 안 된다.

#### A3. 태깅·네이밍 표준 `TF`
1. `providers.tf` 에 `default_tags` — `Project=demo`, `Env`, `Owner`, `ManagedBy=terraform`, `CostCenter`
2. 네이밍 규칙 문서화: `demo-<component>-<seq>` (예: `demo-hub-01`, `demo-eks-01`, `demo-tfstate`)
3. **payer 계정 Billing 콘솔에서 Cost Allocation Tag 활성화** — 활성화 후 24시간이 지나야 데이터가 쌓인다. 지금 안 하면 나중에 비교할 baseline 이 없다
4. (선택) 태그 없는 리소스를 잡는 AWS Config rule 또는 CI 체크

**완료:** 새로 만든 리소스에 태그가 자동으로 붙는다.

#### A4. VPC `TF` — **신규 전용 VPC 를 만든다**
> **결정: 기존 ECS VPC 를 재사용하지 않는다.** 재사용하면 CIDR·서브넷·SG·라우팅이 이미 ECS 에 맞춰져 있어
> EKS 의 IP 요구(노드 서브넷 /19급, 클러스터 X-ENI 전용 서브넷)를 못 맞추고, 실험이 기존 환경을 건드린다.
> 스터디 목적이면 격리된 VPC 가 맞다. 나중에 기존 환경과 통신이 필요해지면 peering/TGW 로 붙인다(§4 백로그).

1. `modules/vpc` — `cidr`, `azs`, 서브넷 크기를 **전부 variable 로** (나중에 VPC 를 쪼갤 때 variable 만 나눠 넣으면 된다)
2. 서브넷 3 AZ:
   - `public` /24 × 3 — ALB
   - `private-node` **/19 × 3** — 노드·파드. **크게 잡는다.** 업그레이드 시 클러스터가 2개 동시에 존재한다
   - `private-controlplane` /28 × 3 — EKS X-ENI 전용 (워커와 섞지 않는다. 컨트롤플레인 업그레이드에 여유 IP 5개가 필요하다)
   - `pod-secondary` /18 × 3 — `100.64.0.0/16` 에서. **지금 만들어만 둔다** (IP 고갈 시 탈출구)
3. NAT Gateway — AZ당 1개. 비용을 줄이려면 1개로 시작할 수 있지만 그러면 AZ 장애 학습이 안 된다
4. 서브넷 태그: `kubernetes.io/role/elb`(public), `kubernetes.io/role/internal-elb`(private), **`karpenter.sh/discovery = demo`**
   > 태그 값을 클러스터 이름으로 하지 않는다 — 서브넷은 허브·워크로드가 공유하고, F6 blue/green 에서 `demo-eks-02` 도 같은 서브넷을 쓴다. 클러스터 이름을 박으면 그때마다 태그를 갈아야 한다. SG 는 클러스터별이므로 SG discovery 태그만 클러스터 이름을 쓴다
5. VPC 엔드포인트: S3(Gateway), ECR api/dkr, STS, EKS — NAT 비용과 지연을 줄인다
6. 출력을 **SSM Parameter Store 로 기록** (`/demo/vpc/private-subnet-ids` 등). 다른 state 는 `terraform_remote_state` 대신 SSM 을 조회한다 — state 간 결합을 피한다

**완료:** VPC 가 뜨고 SSM 에 서브넷 ID 가 있다.

#### A5. ECR + 관측 버킷 + DNS 존 `TF`
1. ECR 리포 — `image_tag_mutability = IMMUTABLE`, `scan_on_push = true`, lifecycle policy(untagged 7일)
   > 멀티계정 대비: 계정이 갈라지면 ECR 은 공유 계정에 남고 워크로드 계정들이 cross-account pull 한다.
   > 그때 repo policy 에 `aws:PrincipalOrgID` 조건으로 org 전체 pull 을 연다 — 지금은 불필요, 그때 추가
2. S3 `demo-thanos` — Thanos 블록 저장. versioning **off**(비용), lifecycle 로 오래된 블록 정리
3. S3 `demo-loki` — 나중 E1 에서 쓴다. 지금 같이 만든다
4. Thanos·Loki 가 쓸 IAM policy 초안 (Pod Identity 로 붙일 것)
5. **Route53 호스팅 존 — EKS 전용 서브도메인** (예: `eks.<도메인>`) + 상위 존에 NS 위임. 존 ID 를 SSM 에 기록
   > B5 의 external-dns·cert-manager 가 이 존을 전제한다. B7 에서 만들면 순서가 꼬인다 — external-dns 는 `--domain-filter` 대상 존이 없으면 무의미하다

**완료:** `docker push` 가 되고, **같은 태그로 재푸시하면 거부된다.** `dig NS` 로 서브도메인 위임이 확인된다.

---

### Phase B — 허브 클러스터

> **왜 이 순서인가 (헷갈리는 부분)**
> ALB 도 없는데 ArgoCD 를 먼저 띄우는 게 거꾸로 보이지만, 순서가 그럴 수밖에 없다:
> **ALB Controller 를 설치하는 주체가 ArgoCD 다** (원칙 2 — 클러스터 안 컴포넌트는 GitOps 소유).
> 그래서 ArgoCD → ALB Controller → Ingress 순이고, 그 사이는 **`kubectl port-forward` 로 다리를 놓는다.**
> ALB Controller 를 Helm 으로 먼저 깔면 부트스트랩 경로가 둘이 되고 원칙 2 가 깨진다.
> 마찬가지로 **관측 스택(B6)보다 StorageClass(B5)가 먼저**다 — Thanos·Grafana·Prometheus 가 전부 PVC 를 쓴다.

#### B1. `modules/eks-cluster` 작성 `TF`
1. `aws_eks_cluster` — `version = var.kubernetes_version` (**"1.34"**)
2. 엔드포인트: `endpoint_public_access = true` + `public_access_cidrs` 로 회사 IP 제한, `endpoint_private_access = true`
3. **`enabled_cluster_log_types = ["api","audit","authenticator","controllerManager","scheduler"]`** — audit log 없으면 아무것도 추적 못 한다
4. Access Entry — `aws_eks_access_entry` + `aws_eks_access_policy_association` (§6.5 표대로)
5. `system` 관리형 노드그룹 — Bottlerocket, **학습용은 1노드 spot t4g.medium**, `taint { key="CriticalAddonsOnly" value="true" effect="NO_SCHEDULE" }`
   > ⚠️ **1노드로 가면 B5-0 에서 Karpenter 를 `replicas: 1` 로 깔아야 한다.** 차트 기본이 `replicas: 2` + hostname 단위 required podAntiAffinity 라 노드 1개면 두 번째 replica 가 영구 Pending. CoreDNS 는 soft antiAffinity 라 1노드 OK.
   > 운영 지향이면 2노드 + Karpenter replicas 2. 여기선 비용 최소가 목적이라 1노드.
6. EKS 애드온 — **버전을 명시**(1.34 호환 최저):
   - `coredns`, `kube-proxy`, `vpc-cni`, `eks-pod-identity-agent`
   - **`aws-ebs-csi-driver`** ← 명시적으로 설치해야 한다. 없으면 **PVC 가 영구 Pending**. 전용 IAM role 필요(`AmazonEBSCSIDriverPolicyV2`, Pod Identity 로 연결)
7. Karpenter 사전 준비 (AWS 쪽): 컨트롤러 IAM role(Pod Identity), 노드 IAM role + instance profile, 중단 이벤트용 SQS + EventBridge rule
8. `lifecycle { prevent_destroy = true }` — 클러스터·노드그룹에
9. 출력: 클러스터 이름·엔드포인트·`certificate_authority` → **SSM 에 기록** (C2 에서 쓴다)

**완료:** 모듈이 apply 되고 출력이 SSM 에 들어간다.

#### B2. `demo-hub-01` 생성 `TF`
1. `live/hub/eks-hub-01/` 에서 모듈 호출 (VPC 정보는 SSM 조회)
2. `aws eks update-kubeconfig --name demo-hub-01`
3. `kubectl get nodes` → 2~3노드, `kubectl describe node | grep Taints` 로 taint 확인
4. `kubectl get pods -A` → CoreDNS·EBS CSI 가 **taint 를 tolerate 하고** 떠 있는지. **안 떠 있으면 여기서 멈추고 toleration 을 고친다**

**완료:** SSO role 로 `kubectl` 이 되고 kube-system 파드가 전부 Running 이다.

#### B3. ArgoCD 설치 — Helm, **사람이 로컬에서** `수동`
> **자동화하지 않는다.** ArgoCD 설치는 최초 1회 + break-glass 때만 필요한데, break-glass 는 속도가
> 생명이라 GitHub Actions 경유가 느리고 GitHub 장애에 취약하다. 이거 하나 자동화하려고 CI role 에
> 클러스터 ClusterAdmin 을 상시 주는 건 과하다. **`admin`(유일한 ClusterAdmin)로 로컬에서 직접 한다.**
> 설치 스크립트는 gitops `platform/hub/argocd/install-argocd.sh` (chart 옆). deploy key 그릇은 `live/bootstrap/argocd-deploy-key.tf`.

1. **values/버전의 진실원천 = gitops `platform/hub/argocd/`** (umbrella chart: `Chart.yaml` 에 argo-cd 버전, `values.yaml` 에 설정)
   - `global.tolerations`: `CriticalAddonsOnly` (system 노드에 떠야 한다)
   - HA **off** 로 시작 · `configs.params."server.insecure": true` (Ingress 는 B7)
2. **Git 레포 자격증명 (deploy key)** — ESO 가 아직 없으므로 수동으로 만든다:
   - `TF`(`argocd-bootstrap` 스택)가 Secrets Manager **시크릿 그릇만** 생성 (값은 state 노출 방지로 TF 에 안 넣음)
   - 사람이 read-only deploy key 생성 → gitops 레포에 등록 → `put-secret-value` 로 값 주입
   - **B5 에서 ESO 가 붙은 뒤 이 Secret 을 ESO 관리로 이관한다**
3. 설치 (로컬, admin): gitops clone → `helm dependency update` → `helm upgrade --install argocd .` → repo Secret 생성
   - 부트스트랩과 self-manage(B4)가 **같은 디렉토리**를 보므로 break-glass 복구 = 평시 상태
4. 접속: `kubectl -n argocd port-forward svc/argocd-server 8080:80`
   비밀번호: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`

**완료:** port-forward 로 ArgoCD UI 에 붙고, Git 레포가 연결돼 있다.
**CI role 에 클러스터 접근을 주지 않았다** — access_entries 는 admin 하나뿐 (권한 최소화).

#### B4. ArgoCD self-manage 전환 `GO`
1. `platform/hub/argocd/` 는 **B3 와 같은 디렉토리** — 이미 `Chart.yaml`(버전) + `values.yaml` 이 진실원천. self-manage Application 이 이걸 가리킨다
   > argocd 는 허브 전용(`platform/hub/`)이라 버전을 여기 둔다 — 허브는 하나뿐이라 overlay 분리 불필요
2. `platform/hub/argocd/root-app.yaml` (app-of-apps) 작성 — `platform/hub/` 를 가리킴. **sync wave 를 처음부터 붙인다**
3. `kubectl apply -f platform/hub/argocd/root-app.yaml` — **이 한 번만 수동** (admin)
4. root-app 이 `platform/hub/argocd` 를 sync → ArgoCD 가 자기를 관리 시작
5. **허브 자신의 cluster Secret** — 이름 `demo-hub-01`, 주소 `https://kubernetes.default.svc`, `argocd.argoproj.io/secret-type: cluster` label. `platform/hub/argocd/` 에 declarative 로 커밋
   > 없으면 C2 의 cluster generator 가 허브를 못 잡는다 — 암묵적 in-cluster 는 Secret 이 아니라서 generator 에 안 걸리고, 잡혀도 이름이 `in-cluster` 라 `overlays/demo-hub-01` 과 매칭이 안 된다
6. **검증:** `values.yaml` 을 Git 에서 바꿔 커밋 → ArgoCD 가 스스로 반영하는지
7. README 에 break-glass 절차 명시

**완료:** ArgoCD 버전·설정을 Git 커밋으로 올릴 수 있다.

#### B5. 허브 기반 애드온 — 여기서 순서가 중요하다 `GO`
> `platform/base/` 는 **허브·워크로드 공통**이다. 허브도 애드온이 필요하다. C4 에서 같은 세트를 워크로드에 쓴다.

0. **Karpenter (허브)** — ⚠️ **B6 보다 반드시 먼저.** `system` 노드그룹은 taint 가 있어 Karpenter·CoreDNS 급만 뜬다.
   **B6 의 Thanos·Grafana·Prometheus 와 이후 Loki·Vault 가 뜰 노드는 Karpenter 가 공급한다** — 허브에 Karpenter 가 없으면 관측 스택 전체가 Pending 이다.
   - 매니페스트는 `platform/base/karpenter/` (허브·워크로드 공통), NodePool 은 overlay 별 — 허브는 `platform` NodePool 1개(on-demand, taint 없음)면 충분
   - IAM·SQS 등 AWS 쪽 준비는 B1-7 이 모듈에 이미 넣었다 (허브도 같은 모듈)
   - 검증·설정 상세는 C3 과 동일 (`expireAfter`, disruption budget, EC2NodeClass AMI 핀)
1. **StorageClass** — `gp3` 를 **default 로 지정** (`provisioner: ebs.csi.aws.com`)
   ⚠️ **B6 보다 먼저여야 한다.** Thanos Receive(WAL)·Compactor(작업공간)·Grafana·Alertmanager·Prometheus 가 전부 PVC 를 쓴다. 없으면 **전부 Pending**
2. **snapshot-controller** — 볼륨 스냅샷의 전제
3. **ESO** — 다른 것들의 시크릿 공급원. Pod Identity 로 SSM·Secrets Manager 읽기
   → 붙은 직후 **B3-4 의 ArgoCD repo Secret 을 ESO 관리로 이관**
4. **metrics-server** — 가볍고 의존이 없다. HPA 의 전제
5. **cert-manager** — TLS 발급 (ACM 을 쓸지 cert-manager 를 쓸지는 B7 에서)
6. **AWS Load Balancer Controller** — Pod Identity 로 IAM. `IngressClass` 정의
7. **external-dns** — ⚠️ `--policy=upsert-only`, `--txt-owner-id=demo-hub-01`, `--domain-filter` 를 **전용 서브도메인으로 제한**

**완료:** `kubectl get sc` 에 default 가 있고, 테스트 PVC 가 Bound 되고, 테스트 Ingress 로 ALB 가 뜬다.

#### B6. 허브 관측 스택 — **하나씩 세운다** `GO`
> 한꺼번에 올리면 어디가 깨졌는지 모른다. 각 단계에서 실제 조회를 확인하고 다음으로 간다.

1. **B6-1 Thanos Receive** — S3 objstore 설정은 **ESO 로**(B5-3), hashring ConfigMap, replica 1, PVC(WAL). Pod Identity 로 S3 권한
2. **B6-2 Thanos Query** — Receive 를 store 로 등록. `/graph` 에서 쿼리 확인
3. **B6-3 Thanos Store Gateway** — S3 과거 블록 조회. Query 에 store 추가. 인덱스 캐시 PVC
4. **B6-4 Thanos Compactor** — ⚠️ **버킷당 반드시 1 replica.** 2개면 블록이 손상된다. downsampling·retention 설정. 작업공간 PVC
5. **B6-5 Grafana** — datasource = Thanos Query. PVC. 대시보드 1개
6. **B6-6 Alertmanager + Thanos Ruler** — 규칙 1개를 일부러 발동시켜 **실제로 알림을 받아본다**
7. **B6-7 허브 자신의 Prometheus** — kube-state-metrics + node-exporter → Receive 로 `remote_write`, `external_labels: cluster=demo-hub-01`

**완료:** Grafana 에서 허브 메트릭이 보이고 알림이 도착한다.

#### B7. 허브 UI 를 Ingress 로 — port-forward 졸업 `GO` `TF`
1. 인증서 — ACM 이냐 cert-manager 냐 여기서 확정 (존은 A5 에서 이미 만들었다) `TF`/`GO`
2. ArgoCD·Grafana 에 Ingress — B5-6 의 `IngressClass`, `group.name` 으로 **ALB 1개 공유**
3. `configs.params."server.insecure"` 를 되돌리고 TLS 종료를 ALB 로
4. 접근 제한 — 내부 ALB 또는 SG/WAF. (SSO 는 E5 oauth2-proxy 에서)

**완료:** 도메인으로 ArgoCD·Grafana 에 접속된다. port-forward 는 이제 비상용이다.

---

### Phase C — 워크로드 클러스터

#### C1. `demo-eks-01` 생성 `TF`
B1 모듈 재사용(**같은 Git tag**). `live/workload/eks-01/`. 버전·애드온 모두 허브와 동일(1.34).
**완료:** 클러스터가 뜨고 SSM 에 출력이 들어간다.

#### C2. 스포크 등록 자동화 `TF` `GO`
1. `TF` `modules/spoke-registration`:
   - 스포크 IAM role `argocd-spoke` — **권한 정책 없음.** 허브 management role 만 assume 가능한 trust
   - 그 role 에 **EKS Access Entry** + 최소 권한
   - 허브 management role 에 `sts:AssumeRole` + `sts:TagSession` 추가
   - 클러스터 메타데이터를 **SSM 파라미터로 기록** (name / endpoint / caData / roleARN)
2. `GO` 허브의 ESO(B5-3)에 `ClusterSecretStore`(SSM) + `ExternalSecret` → **`argocd.argoproj.io/secret-type: cluster` label 이 붙은 cluster Secret 생성**
3. `GO` `clusters/platform-appset.yaml` — ApplicationSet **cluster generator**, `platform/overlays/{{name}}`
4. **검증:** `argocd cluster list` 에 `demo-eks-01` 이 보이고 Application 이 **자동 생성**되는지

**완료:** **`kubectl` 수동 단계 0** 으로 워크로드 클러스터가 허브에 등록된다.

#### C3. Karpenter (워크로드) `GO`
> C4 보다 먼저다. 애드온이 뜰 노드 용량을 Karpenter 가 공급한다 (`system` 은 부트스트랩 전용이라 자리가 없다).
> 허브는 B5-0 에서 이미 설치했다 — 여기는 같은 `platform/base/karpenter/` 를 워크로드 overlay 로 적용하고, NodePool 만 env 별로 나눈다.

1. Karpenter 차트의 **EKS 1.34 호환 버전 확인** 후 고정
2. Helm 설치 — 차트 기본값 확인:
   - `replicas: 2` + hostname required podAntiAffinity + zone `DoNotSchedule`
   - `tolerations: [{key: CriticalAddonsOnly, operator: Exists}]`
   - `affinity.nodeAffinity`: `karpenter.sh/nodepool DoesNotExist` ← 자기가 만든 노드에 뜨는 것을 스스로 막는다
3. `EC2NodeClass` — `amiFamily: Bottlerocket`, **`amiSelectorTerms` 에 alias + 버전 핀**(`@latest` 금지), subnet/SG selector 는 A4 의 `karpenter.sh/discovery` 태그로
4. `NodePool` 2개 — `prod`(taint `env=prod`, on-demand, 업무시간 disruption 0%) / `nonprod`(taint `env=nonprod`, spot 우선, consolidation 공격적). 둘 다 **`expireAfter: 720h` 명시**
5. **검증:** Deployment replica 를 늘려 노드가 뜨는지 → 줄여 consolidation 으로 사라지는지. `kubectl get nodeclaims` 로 관찰

**완료:** Karpenter 가 노드를 띄우고 정리한다.

#### C4. 워크로드 기반 애드온 `GO`
**B5 와 같은 `platform/base/` 세트**를 `overlays/demo-eks-01/` 로 적용 — StorageClass → snapshot-controller → ESO → metrics-server → cert-manager → ALB Controller → external-dns.
추가로 워크로드에만:
- **KEDA**
- **Kyverno** — **CEL 정책 타입**(`ValidatingPolicy` 등). 구 `ClusterPolicy` 는 deprecated. 전부 `Audit` 으로 시작. `kube-system`·플랫폼 namespace 는 webhook 제외, replica 2+, `webhookTimeoutSeconds` 10 이하
- **node-problem-detector**
- **efs-csi** (기준 1 의 "상태는 EFS 로 밖에" 를 쓰려면)
- **fluent-bit** — 지금은 stdout 확인만. Loki 연결은 E1

**완료:** Ingress 로 ALB 가 뜨고, 테스트 PVC 가 Bound 되고, HPA 가 동작한다.

#### C5. 멀티테넌시 `GO`
1. `PriorityClass` 4개 — `prod(1000) > uat(700) > qa(400) > dev(100)`. 플랫폼 컴포넌트는 `system-cluster-critical`
2. **Kyverno `GeneratingPolicy`** — namespace 생성 시 `ResourceQuota` + `LimitRange` + `NetworkPolicy`(default-deny) **자동 부착**
3. **Kyverno `ValidatingPolicy`** — request 필수 / `preStop` 필수 / PDB 필수 / `latest` 금지 / ECR allowlist / IngressClass allowlist / **`env` 라벨 필수**(NodePool taint 매칭용)
4. Pod Security Admission — namespace 라벨 `enforce=baseline, warn=restricted, audit=restricted` 로 시작
5. **`Audit` → 위반 정리 → `Enforce` 승격**
6. **검증:** dev toleration 파드가 prod NodePool 에 못 뜨는지, request 없는 파드가 거부되는지
7. ⚠️ **VPC CNI network policy 는 파드 기동 직후 잠깐 정책 미적용 창이 있다** (정책이 eventually 적용됨) — default-deny 를 보안 경계로 믿는다면 network policy agent 의 **strict mode** 적용 여부를 여기서 결정하고 문서화한다

**완료:** dev 가 prod 노드를 못 건드리고, 표준 미준수 파드가 거부된다.

#### C6. 메트릭 연결 `GO`
워크로드 Prometheus + kube-state-metrics + node-exporter → 허브 Thanos Receive `remote_write`. `external_labels: cluster=demo-eks-01`.
**완료:** 허브 Grafana 에서 두 클러스터를 구분해서 본다.

---

### Phase D — 첫 서비스

#### D1. 골든 템플릿 `GO`
`apps/_template/base/` 에 표준 세트: Rollout(또는 Deployment) · Service · Ingress · HPA(`scaleTargetRef`→Rollout) · PDB · ServiceAccount · NetworkPolicy · `terminationGracePeriodSeconds` · **`preStop` 5~10초 sleep** · `topologySpreadConstraints` · probe 3종.
리소스 규칙: **memory `request == limit`**, **cpu 는 request 만(limit 없음)**.
Kustomize `openapi` 설정 — 없으면 Rollout CRD 에 image transformer 가 **조용히 미적용**된다.
**완료:** 새 서비스가 overlay 1개 작성으로 올라간다.

#### D2. 첫 서비스 + canary `GO`
1. 앱 레포 CI: build → ECR push(`sha-<gitsha>`) → **digest 를 gitops overlay 에 커밋**
2. dev namespace 에 배포 → ArgoCD sync 확인
3. prod namespace 에 Argo Rollouts canary — 10% → 50% → 100%
4. **검증:** 카나리 가중치가 **ALB 타겟그룹 실측으로** 반영되는지 (UI 표시만 믿지 않는다)

**완료:** 카나리가 실제 트래픽을 나눈다.

---

### Phase E — 나머지 플랫폼

| # | 항목 | 핵심 |
|---|---|---|
| E1 | **Loki**(허브) + fluent-bit(워크로드) | S3 백엔드, retention. Grafana 에서 메트릭↔로그 이동 확인 |
| E2 | **Vault**(허브) | Raft HA, **스냅샷 백업 필수**(없으면 허브 유실 시 시크릿 영구 상실), k8s auth → ESO 백엔드를 Secrets Manager 에서 Vault 로 교체, `reloader` 로 파드 갱신 확인 |
| E3 | OpenCost | 팀별 비용. A3 태그가 전제 |
| E4 | policy-reporter | Kyverno 위반 집계 UI |
| E5 | oauth2-proxy | 허브 UI 3개(ArgoCD·Grafana·policy-reporter) SSO |
| E6 | Backstage | 서비스 카탈로그. 서비스가 여러 개 올라간 뒤에 의미가 있다 |

---

### Phase F — 업그레이드 스터디 (이게 목표였다)

쉬운 것부터 어려운 것 순서다. **한 번에 하나만 올린다.**
§1 의 1.35/1.36 breaking change 목록은 작성 시점 정보다 — **F3·F4 착수 시점에 해당 버전 릴리스 노트와 `list-insights` 로 재검증**하고 시작한다.

| # | 무엇 | 배우는 것 |
|---|---|---|
| **F1** | EKS 애드온 마이너 1개 올리기 (CoreDNS 등) | 가장 안전한 연습. `describe-addon-versions` → `resolve_conflicts` → 롤백 |
| **F2** | Helm 차트 1개 올리기 (Grafana 또는 Thanos) | CRD 업그레이드, values 스키마 변경 대응, ArgoCD sync wave |
| **F3** | **EKS 1.34 → 1.35 in-place** | `list-insights` 로 사전 점검 → **허브 먼저 → 1주 관찰 → 워크로드**. cgroup v1·containerd 1.x·IPVS deprecation 대응. **7일 롤백 창은 컨트롤플레인만이다** — 노드·애드온은 별도(§6.4) |
| **F4** | **EKS 1.35 → 1.36 in-place** | `gitRepo` 볼륨 제거, **`StrictIPCIDRValidation`** (매니페스트의 비정규 CIDR 전수 점검), IPVS 제거 |
| **F5** | 노드 AMI 버전 올리기 | AMI 핀 변경 → Karpenter drift 자동 교체 → disruption budget 이 실제로 속도를 제한하는지 관찰 |
| **F6** | **blue/green — `demo-eks-02` 를 Cilium 으로** | 새 클러스터 생성 → cluster Secret 등록 → cluster generator 가 자동 편입 → 트래픽 이동 → `-01` 삭제. **소모품 클러스터 실습과 Cilium 학습이 하나로.** 재구축 RTO 실측 |

**F6 을 마지막에 두는 이유:** 앞의 F1~F5 로 in-place 경로를 다 걸어본 뒤에 blue/green 을 해야 두 경로를 비교할 수 있다.

---

## 4. 나중에 할 것

우선순위 최하. **"안 한다" 가 아니라 "지금은 안 한다".** 꺼낼 조건을 적어둔다 — 조건 없이 미루면 잊혀진다.

| 항목 | 왜 지금은 아닌가 | 언제 꺼내나 |
|---|---|---|
| **Tempo** (트레이싱) | Tempo 는 APM 이 아니라 트레이스 저장·조회 백엔드일 뿐. **트레이스는 서비스가 서로 호출해야 의미가 생긴다.** 계측만 OTel 로 고정해두면 나중에 붙이기 쉽다 | 서비스 5개 이상이 서로 호출할 때 |
| **Cilium** (CNI 교체) | VPC CNI 로 default-deny 를 먼저 세우는 게 급하다. 1일차에 넣으면 CNI 교체와 정책 학습을 동시에 하는 셈 | **F6 blue/green 때 새 클러스터를 Cilium 으로 세워 갈아탄다** — 소모품 클러스터 실습과 Cilium 학습이 하나로 합쳐진다 |
| **Velero** (백업/복구) | 중요하지만 **아직 백업할 상태가 없다.** 매니페스트는 Git 이 진실원천이고 PV 가 없다 | PV·stateful 이 생길 때. **또는 F6 직전** — 그때 실제 복구를 검증 |
| Pyroscope (프로파일링) | APM 의 "어느 함수가 느린가". 트레이싱보다 뒤 | Tempo 이후 |
| private-only EKS 엔드포인트 | 초기엔 public+private 로 디버깅 마찰을 줄인다 | B5 애드온이 다 붙은 뒤 |
| **기존 ECS VPC 와 연결** (peering 또는 TGW) | EKS 전용 VPC 로 격리해서 시작했다. 지금은 붙일 이유가 없다 | EKS 의 앱이 기존 RDS·ElastiCache·내부 ALB 를 호출해야 할 때. **그때 해당 SG 규칙에 EKS 쪽 출처를 추가하는 작업이 따라온다** |
| cross-account 스포크 등록 | 같은 계정으로 시작해서 IAM trust 한 겹이 미뤄졌다 | 두 번째 계정에 클러스터를 만들 때. **그때 같이 필요한 것:** ① 그 계정에 OIDC provider + CI role + state 버킷(`demo-terraform-tfstate-<별칭>`) 부트스트랩, ② 허브 ESO 의 SSM 읽기를 cross-account role assume 으로, ③ 스포크 Prometheus → 허브 Thanos Receive 의 **네트워크 경로**(peering/TGW 또는 public+인증) |
| Gateway API | Ingress 로 충분 | ALB Ingress 로 표현 못 하는 요구가 생길 때 |
| 서비스메시 | 1일차 도입은 실패율을 배로 올린다 | mTLS 규제 요구가 생기면 |
| ECS 마이그레이션 (226개) | 플랫폼이 먼저 선다. D2(첫 서비스) 이후 실측으로 처리량을 재고 일정을 역산한다 | D1~D2 완료 후 |
| ~~Crossplane · ACK~~ | **미채택** (보류 아님). Terraform 과 AWS 리소스 소유권이 충돌한다 | Terraform 을 걷어낼 결정을 하면 |

---

## 5. 아직 안 정한 것

| 항목 | 언제까지 |
|---|---|
| VPC CIDR 실제 값 · 서브넷 분할 | **A4 전** — 기존 VPC 들과 겹치지 않는 대역을 골라야 한다 (나중에 peering 하려면 CIDR 중복이 치명적) |
| NodePool 을 환경별 말고 워크로드 유형별로도 쪼갤지, spot 비율 | C3 전 |
| Namespace 명명 규칙 (`<service>-<env>` 확정 여부) | C5 전 |
| ResourceQuota 실제 수치 | C5 전 |
| 서비스별 리소스 request/limit 기준값 | D1~D2 (첫 서비스 실측으로) |

---

## 6. 상세 — 필요할 때만 본다

### 6.1 스포크 클러스터 등록 (C2)

새 클러스터를 만들면 허브 ArgoCD 에 4가지가 필요하다. TF 쪽 셋은 `modules/spoke-registration` 에 넣어 `terraform apply` 하나로 끝낸다.

| # | 만드는 것 | 어디 |
|---|---|---|
| 1 | 스포크 IAM role — 권한 정책 없음, 허브 management role 만 assume 가능한 trust 만 | TF |
| 2 | 그 role 에 대한 **EKS Access Entry** + 최소 권한 정책 | TF |
| 3 | 허브 management role 의 `sts:AssumeRole` 대상에 #1 추가 (+`sts:TagSession`) | TF |
| 4 | 허브의 ArgoCD **cluster Secret** (`argocd.argoproj.io/secret-type: cluster` label) | GitOps |

#4 만 K8s API 쓰기라 원칙 2 위반이다. Terraform 이 직접 넣지 않는다:

```
terraform apply → 클러스터 메타데이터(name/endpoint/caData/roleARN)를 SSM 파라미터로 기록
                → 허브의 ESO 가 읽어 cluster Secret 으로 동기화 (label 포함)
                → ApplicationSet cluster generator 가 Secret 감지 → Application 자동 생성 → sync
```

삭제는 역순: 파라미터 삭제 → Secret 소멸 → Application 소멸 → `terraform destroy`.
**`kubectl` 수동 단계가 0 이어야 원칙 1 이 말로만 성립하지 않는다.**

```yaml
# cluster Secret 의 config 필드
{
  "awsAuthConfig": { "clusterName": "demo-eks-01", "roleARN": "arn:aws:iam::<acct>:role/argocd-spoke" },
  "tlsClientConfig": { "insecure": false, "caData": "<base64>" }
}
```

### 6.2 멀티테넌시 (C5) — 단일 클러스터의 핵심 통제

클러스터 하나가 dev~prod 를 다 담으므로 **나중에 하면 안 된다.**

| 통제 | 없으면 |
|---|---|
| `LimitRange` (default request/limit) | request 없는 파드가 prod 노드를 먹는다 |
| `ResourceQuota` (환경별 차등) | dev 가 클러스터 용량을 다 쓴다 |
| `PriorityClass` `prod(1000)>uat(700)>qa(400)>dev(100)` | 노드 압박 시 prod 가 먼저 축출될 수 있다 |
| **Karpenter NodePool 을 taint 로 물리 분리** | dev 폭주 파드가 prod 파드와 같은 노드 커널·메모리를 공유한다 |
| `NetworkPolicy` default-deny | dev 파드가 prod 서비스를 호출할 수 있다 |
| `topologySpreadConstraints` (AZ + host) | 노드 하나 빠질 때 서비스가 통째로 내려간다 |

**NodePool taint 분리가 핵심이다.** ResourceQuota 는 총량만 막고 같은 노드에 뜨는 것 자체를 못 막는다.
전부 **Kyverno 로 강제**한다. 권고로 두면 절반이 빠진다.

### 6.3 NodePool / Karpenter (B5-0 · C3)

```
관리형 노드그룹 (Terraform) — 허브·워크로드 공통
  system: 2~3 노드, on-demand, taint CriticalAddonsOnly=true:NoSchedule
    → Karpenter 자신 · CoreDNS · metrics-server 만
    → Karpenter 가 자기가 만든 노드에 떠 있으면 자기 노드를 지우고 자살한다

Karpenter NodePool (GitOps) — overlay 별로 다르다
  [허브 demo-hub-01]
  platform: taint 없음, on-demand
            → ArgoCD·Thanos·Grafana·Loki·Vault 등 허브 스택이 뜨는 곳
  [워크로드 demo-eks-01]
  prod:     taint env=prod:NoSchedule, on-demand 100%(초기)
            consolidation WhenEmptyOrUnderutilized + budgets 로 업무시간 0%
  nonprod:  taint env=nonprod:NoSchedule, spot 우선, consolidation 공격적
```

- **`expireAfter` 를 명시한다 (권고 30일).** Auto Mode 가 강제하던 노드 순환이 사라졌으므로, 안 정하면 노드가 몇 달 살아남아 커널 패치가 안 된다
- **disruption budget** 으로 동시 교체 수를 제한한다. PDB 만으로는 한꺼번에 여러 노드가 비워질 수 있다
- **PDB + `terminationGracePeriodSeconds` + `preStop`(5~10초 sleep) 필수.** consolidation 이 상시 파드를 옮긴다. `preStop` 이 없으면 ALB IP 모드에서 타겟그룹에서 빠지기 전에 SIGTERM 을 받아 요청을 흘린다
- 리소스 규칙: **memory 는 `request == limit`**, **cpu 는 request 만 (limit 없음)** — cpu limit 은 CFS throttling 이라 "EKS 가 느리다" 의 최다 원인이다. JVM 은 `MaxRAMPercentage` 명시

### 6.4 업그레이드 (Phase F, 이후 상시)

**목표 N-1. extended support 진입 금지** (클러스터 시간당 $0.10 → $0.60). **분기 1회 윈도우** (연 3 마이너).

```
사전 (윈도우 2주 전)
  aws eks list-insights                                    # deprecated API 탐지
  aws eks describe-addon-versions --kubernetes-version <target>   # 애드온 지원 확인

순서 — 허브가 카나리다
  1. 허브: 컨트롤플레인 → 애드온 → 노드
  2. 1주 관찰 (허브가 깨져도 워크로드 클러스터는 멀쩡)
  3. 워크로드: 컨트롤플레인 → 애드온 → 노드

애드온: 컨트롤플레인 업그레이드로 자동 갱신되지 않는다. 별도 승격, 한 번에 1 마이너
노드:  AMI 핀을 올리면 Karpenter drift 가 자동 교체. disruption budget 으로 속도 제한
       `system` 노드그룹은 별도 절차 (managed node group update)
롤백:  컨트롤플레인 마이너는 업그레이드 후 7일 내 롤백 가능 (2026-07 출시 기능)
       단 ① 노드가 컨트롤플레인보다 새 버전이면 안 된다 — 노드 먼저 롤백
          ② 애드온은 자동 롤백되지 않는다 — 별도로 내린다
       그 창을 넘기면 blue/green 뿐
```

### 6.5 RBAC (B1-4)

**Access Entry 를 쓴다. `aws-auth` ConfigMap 은 안 쓴다** (ConfigMap 편집 실수로 클러스터 접근을 통째로 잃는 사고를 없앤다).

| 주체 | Access Entry 정책 | 범위 |
|---|---|---|
| 플랫폼팀 (SSO role) | `AmazonEKSClusterAdminPolicy` | 클러스터 전체 |
| 앱팀 (SSO role, 팀별) | `AmazonEKSEditPolicy` + namespace 스코프 | 자기 팀 namespace |
| 조회 전용 | `AmazonEKSViewPolicy` | 클러스터 전체 |
| ArgoCD (`argocd-spoke`) | 전용 ClusterRole (Edit 보다 좁게) | 클러스터 전체 |
| break-glass / 부트스트랩 (사람, `admin`) | `AmazonEKSClusterAdminPolicy` | ArgoCD 최초 설치·복구도 이 신원으로 로컬에서 |

> **CI role(`demo-gha-terraform`)은 이 표에 없다 — 의도적.** Terraform apply 는 IAM API 만으로 되므로 클러스터 접근이 필요 없다.
> ArgoCD 설치·break-glass 같은 클러스터 안 작업은 사람이 `admin` 로 로컬에서 한다 — 자동화 하나 때문에 CI 에 ClusterAdmin 을 상시 주지 않는다(권한 최소화).

- 사람을 개별 등록하지 않는다 — **SSO permission set → IAM role 단위** (Access Entry 는 클러스터당 3,000개 상한)
- **컨트롤플레인 audit log 를 켠다.** 없으면 누가 무엇을 했는지 못 보고, 업그레이드 전 deprecated API 탐지도 못 한다
