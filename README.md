# eks-hub-spoke-gitops

EKS 멀티클러스터 플랫폼 한 벌. **허브/스포크** 구조로, 허브가 ArgoCD·관측(Thanos·Loki·Grafana)을
중앙에서 들고, 스포크는 워크로드를 돌리고 지표·로그를 허브로 push 한다.

레포는 **수명주기 경계**로 둘로 나뉜다 — AWS 리소스는 Terraform, 클러스터 안은 GitOps.

| 디렉토리 | 담당 | 도구 |
|---|---|---|
| [`infra-terraform/`](./infra-terraform) | VPC·EKS·IAM·ECR·Route53·S3(관측/state) | Terraform |
| [`eks-gitops/`](./eks-gitops) | ArgoCD·애드온·앱 매니페스트 (hub/spoke) | ArgoCD + Helm/Kustomize |

## 원칙 5

1. **클러스터는 소모품** — 이름에 시퀀스(`-01`), 상태는 Git·S3 에 (예외: 허브)
2. **Terraform / GitOps 경계 = 수명주기** — TF 에서 `helm_release`·`kubernetes_manifest` 금지
3. **환경은 디렉토리다, 브랜치가 아니다** — `main` 하나
4. **이미지 태그는 불변** — 승격은 digest(`@sha256:`)
5. **관측이 워크로드보다 먼저**

## 아키텍처

GitOps 로 애드온을 까는 흐름 — 최초에 app-of-apps 를 허브·스포크 각각 한 번씩 `kubectl apply` 하면
나머지는 ArgoCD 가 전부 자동 배포한다. 스포크는 클러스터가 등록되는 순간 세트 전체가 따라붙는다.

![GitOps addon 설치 흐름](eks-gitops/architecture/addon-install-flow.png)

애드온 연결 지도 — 허브는 조회·보관·배포가 모이는 곳, 스포크는 수집·집행 후 허브로 push.
클러스터 경계를 넘는 흐름은 internal NLB 를 지난다.

![애드온 아키텍처](eks-gitops/architecture/connection-map.png)

## 메모

- 예시용으로 계정 ID·도메인·IP 등 환경값은 placeholder(`111111111111`, `example.com`, `your-org` …)로 치환돼 있다.
- 시크릿은 레포에 없다 — 전부 AWS Secrets Manager / SSM 에 두고 External Secrets 로 주입한다.
