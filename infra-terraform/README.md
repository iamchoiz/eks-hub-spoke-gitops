# infra-terraform

EKS 플랫폼의 **AWS 쪽 절반**. 클러스터 안 절반은 [`eks-gitops`](../eks-gitops).
전체 계획: [`EKS-MIGRATION-PLAN.md`](./EKS-MIGRATION-PLAN.md) · 프레젠테이션: `open EKS-MIGRATION-DECK.html`

## 원칙 5 — 여기서 벗어나는 PR 은 머지하지 않는다

1. **클러스터는 소모품이다** — 이름에 시퀀스(`-01`), 상태는 Git·S3 에. *예외: 허브*
2. **Terraform / GitOps 경계 = 수명주기** — `helm_release`·`kubernetes_manifest` **금지, 예외 0개**
3. **환경은 디렉토리다, 브랜치가 아니다** — `main` 하나
4. **이미지 태그는 불변** — 승격은 digest(`@sha256:`)
5. **관측이 워크로드보다 먼저**

## 소유권 — 무엇이 이 레포인가

| 대상 | 레포 |
|---|---|
| VPC · 서브넷 · SG · NAT · VPC 엔드포인트 | **여기** |
| EKS 컨트롤플레인 · EKS 애드온 버전 | **여기** |
| `system` 노드그룹 · Karpenter 용 IAM/인스턴스 프로파일/SQS | **여기** |
| IAM role · Pod Identity association · Access Entry | **여기** |
| ECR · S3(thanos/loki/state) · Route53 존 · SSM 파라미터 | **여기** |
| ArgoCD 부트스트랩 워크플로 (`.github/workflows/`) | **여기** — Terraform 리소스가 아니다 |
| Karpenter NodePool · EC2NodeClass | gitops ← 노드는 AWS 리소스지만 **선언은 K8s API** |
| 애드온 워크로드 · ArgoCD 자신 · 앱 매니페스트 · Namespace/Quota | gitops |

## 디렉토리

```
modules/          # 버전 태그(?ref=vX.Y.Z)로만 참조한다 — 상대경로 금지
live/             # 이 repo = demo 플랫폼(1계정). 다른 플랫폼 = 다른 repo
  bootstrap/      # state 버킷 + GitHub OIDC (수동 apply 는 최초 1회뿐)
  shared/         # vpc / ecr / s3-observability / dns — 클러스터보다 오래 산다
  hub/eks-hub-01/     # 클러스터 1개 = 1 state. 절대 합치지 않는다
  workload/eks-01/
```
> 플랫폼 경계는 **repo** 가 잡는다 (infra-terraform ↔ eks-gitops).
> 같은 플랫폼에 계정이 여러 개(dev/prod) 생기면 그때 `live/<계정역할>/` 도입 (플랫폼 이름 금지 — repo 와 중복).
> state key 는 여전히 `demo/<stack>/…` prefix (계정 식별용, 버킷은 계정당 1개).

## 운영 규칙

- state 는 `s3://demo-tfstate-111111111111` (`use_lockfile`). state 간 참조는 **SSM**, `terraform_remote_state` 금지
- 버전은 전부 variable+tfvars · `for_each` 사용 · 리팩터링은 `moved` 블록
- CI 가 plan JSON 의 **delete 액션을 차단**한다 — 의도된 삭제는 PR 에서 명시적으로 풀 것
- apply 는 GitHub Actions(OIDC) 로만. 로컬 apply 는 break-glass
