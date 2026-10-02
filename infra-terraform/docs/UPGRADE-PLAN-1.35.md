# EKS 업그레이드 — 1.34 → 1.35

> 스포크 blue/green + 허브 in-place. 정책 = [`UPGRADE-POLICY.md`](./UPGRADE-POLICY.md). 완료 후 PROGRESS 이전 + 삭제.
> 버전 제어 = sync: git 엔 새 버전 하나, **blue(eks-01) sync 금지 → 옛 버전 유지 / green(eks-02) sync → 새 버전 fresh.**
> 게이트: `list-insights` deprecated API 없음 (양 클러스터, 2026-09-28 실측).

## 순서

```
0. auto-sync off  +  blue sync 금지
1. git 버전 상향 (커밋만)
2. green(demo-eks-02) 신설 @1.35 → 등록 → green 만 sync
3. green 검증 (트래픽 0)
4. DNS 커트오버 blue → green
5. blue(demo-eks-01) destroy
6. 허브 in-place (애드온 sync → CP+5종 apply → 관찰)
7. auto-sync 원복 → 기록 → 삭제
```

## 0. 준비

- 스포크 appset 템플릿 `syncPolicy.automated` 제거 (`platform/spoke/_appsets/*`) + 허브 app-of-apps → 전부 수동.
- **blue(`demo-eks-01`) sync 금지** (실수 sync = 새 버전 점프, ESO CRD 마이그레이션 되돌리기 어려움).
- 끝나면 auto-sync 원복 (step 7).

## 1. git 버전 상향 (커밋만)

| 애드온 | 현재 → 타겟 | 파일 |
|---|---|---|
| KEDA | 2.17.3 → **2.21.0** | `platform/spoke/_appsets/keda-appset.yaml:24` |
| cert-manager | v1.16.2 → **v1.21.2** | 허브 `platform/hub/_apps/cert-manager.yaml:13` · 스포크 `platform/spoke/_appsets/cert-manager-appset.yaml:24` |
| ESO | 0.10.7 → **2.11.0** | 허브 `platform/hub/_apps/external-secrets.yaml:13` · 스포크 `platform/spoke/_appsets/external-secrets-appset.yaml:24` |
| (선택) argo-rollouts | 2.40.7 → 2.43.2 | `platform/spoke/_appsets/argo-rollouts-appset.yaml:24` |

ESO apiVersion `external-secrets.io/v1beta1 → v1` (7파일):
`platform/hub/eso/secrets-manager-secret-store.yaml:1` · `platform/hub/argocd/templates/github-sso-externalsecret.yaml:4` · `platform/hub/kube-prometheus-stack/templates/grafana-externalsecret.yaml:6` · `platform/hub/policy-reporter/templates/policy-reporter-oauth-externalsecret.yaml:3` · `platform/spoke/eso-resources/secrets-manager-secret-store.yaml:1` · `clusters/spoke-demo-eks-01.yaml:1` · `apps/demo-app/chart/templates/external-secret.yaml:3`

## 2. green 신설 (`demo-eks-02`)

- TF `live/workload/eks-02/` (eks-01 복제): `cluster_version = "1.35"`, `addon_versions` 5종:
  coredns `v1.13.2-eksbuild.31` · kube_proxy `v1.35.3-eksbuild.29` · vpc_cni `v1.22.4-eksbuild.3` · pod_identity `v1.3.10-eksbuild.3` · ebs_csi `v1.66.0-eksbuild.1`
- 등록 `clusters/spoke-demo-eks-02.yaml` (eks-01 복제). **apiVersion `v1beta1` 유지**(허브 ESO 0.10 이 처리 — v1 로 하면 등록 깨짐). 라벨 `demo.io/workload=true` + env + `demo.io/dns-weight: "0"`(green dark).
- ⚠️ 스포크-처리 ExternalSecret 만 v1: `platform/spoke/eso-resources/*`, `apps/demo-app/chart/templates/external-secret.yaml` (green ESO 2.x). 허브것·등록것은 v1beta1.
- green child Application **수동 sync** → 애드온·앱 fresh 전개. blue 는 OutOfSync 떠도 그대로 둠.

## 3. green 검증 (트래픽 0)

`--context demo-eks-02`: 전 애드온 Healthy, ESO SecretSynced, KEDA ScaledObject READY, PVC Bound, demo-app 파드·ingress·healthcheck 정상.

## 4. 트래픽 커트오버 blue → green — Route53 weighted (canary)

**전략 = Route53 가중치 라우팅** (실무 표준 — [AWS 블로그](https://aws.amazon.com/blogs/containers/blue-green-or-canary-amazon-eks-clusters-migration-for-stateless-argocd-workloads/): ArgoCD EKS 클러스터 blue/green 정석). 레코드를 **삭제하지 않고** 같은 호스트에 blue·green 둘 다 두고 가중치로 트래픽 이동 → **다운타임 0, canary, 즉시 롤백**.

**구현(완료)**: 골든차트 ingress 가 external-dns 어노테이션 렌더 —
`set-identifier`=클러스터명(appset `{{.name}}` 주입), `aws-weight`=cluster Secret 라벨 `demo.io/dns-weight`(blue 100 / green 0).
set-identifier 가 클러스터별로 달라 Route53 에서 별개 레코드 = owner 충돌 없음. ⚠️ external-dns `policy=upsert-only` 필수(sync 면 다른 set-id 삭제 — 이미 upsert-only).

**커트오버 절차 (green weight 만 올림):**
```
green dns-weight  0 → 10  : canary. Grafana 에서 blue vs green 에러율/지연 비교
                              (green 은 cluster=demo-eks-02 로 허브 Loki/Thanos 에 이미 들어옴)
              → 50 → 100  : 점진 확대
blue dns-weight 100 → 0   : green 100 확인 후 blue 뺌
```
- green weight 조정 = `clusters/spoke-demo-eks-02.yaml` 의 `demo.io/dns-weight` 값 변경 → commit → sync (또는 canary 중 빠른 조정은 Route53 콘솔 후 값 정합)
- 검증: `dig www.eks…`(가중치 반영), `curl -sI https://www.eks.example.com` 반복 → green ALB 비율

**⚠️ 이번 회차 한정 함정 (blue frozen):**
1. **초기 simple→weighted 전환**: 현재 `www.eks` 는 simple 레코드. Route53 은 같은 이름 simple+weighted 공존 불가 → green 이 weighted 만들려면 blue 레코드부터 weighted 여야 함. **blue 는 frozen(git sync 시 ESO v1 로 깨짐)이라 blue ingress 어노테이션을 GitOps 로 못 바꿈** → blue 쪽 weighted 레코드는 **Route53 change-batch 로 수동 전환**(DELETE simple + CREATE weighted set-id=demo-eks-01 w=100 을 한 배치 = near-zero gap).
2. blue weight 낮추기도 blue frozen 이라 Route53 에서 직접(또는 blue external-dns 정지 후).
3. green 쪽은 전부 declarative (라벨 weight). → **다음 회차(F6, 양쪽 호환 config)부터는 blue·green 둘 다 선언적 = 수동 Route53 불필요.**

**`thanos-sidecar.eks`(메트릭)**: 하드코딩 공유 레코드라 커트오버 시 같이 flip 필요(허브가 green 메트릭 보게). 앱 canary 와 별개 — 최종 100% 시점에 맞추면 됨. (정식 멀티클러스터는 `thanos-sidecar-{{.name}}` + 허브 Query 2엔드포인트 — F6 정식화 후보)

## 5. blue destroy

`demo-eks-01` tf destroy → `clusters/spoke-demo-eks-01.yaml` 삭제 (Application 소멸). green 안정 확인 후.

## 6. 허브 in-place

- 애드온 sync: `platform/hub/_apps/{cert-manager,external-secrets}.yaml` (허브 ESO 0.10→2.x 라이브 마이그레이션, 트래픽 0). `externalsecret,clustersecretstore` SecretSynced 확인.
- `live/hub/eks-hub-01/terraform.auto.tfvars`: `kubernetes_version = "1.35"` + `addon_versions` 5종 (10/1 리팩터로 variables.tf → tfvars 이동. ✅ 2026-10-01 반영됨 — green eks-02 와 동일 값).
  ```bash
  cd ~/Documents/eks-project/infra-terraform/live/hub/eks-hub-01
  terraform plan -out=tfplan && terraform show tfplan | grep -E "will be|~ "
  ```
  diff = CP + 애드온 5종 + MNG 버전만 → apply. 관찰 §검증.

## 7. 마무리

auto-sync 원복. Karpenter 노드 1.35 확인. PROGRESS 기록 → 이 문서 삭제.

---

## 안 건드림 (1.35 호환)

Karpenter 1.9.2 · ArgoCD v3.4.6 · Kyverno 3.9.1 · kube-prometheus-stack 91.4.1 · metrics-server 3.12.2 · ALB controller 1.10.1 · external-dns 1.15.2 · alloy · loki · thanos · policy-reporter · NPD. 노드 AMI(1.65.0) 변경 불필요(alias 자동 해석).

## 검증 (context 만 교체)

```bash
kubectl --context demo-eks-02 get nodes -o wide           # Ready, v1.35.x
argocd app list | grep -v Healthy                         # 빈 출력 정상
kubectl --context demo-eks-02 get externalsecret,pvc -A    # SecretSynced / Bound
kubectl --context demo-eks-02 run dns --rm -it --image=busybox --restart=Never -- nslookup www.google.com
aws eks list-insights --cluster-name demo-eks-02 --region ap-northeast-2 \
  --query 'insights[?insightStatus.status!=`PASSING`].[name,insightStatus.status]' --output table
```

## 롤백

| 대상 | 방법 |
|---|---|
| 스포크 트래픽 | **weight 되돌리기 = 즉시 롤백** (green weight↓, blue weight↑). 레코드 안 지우니 무중단. blue destroy 는 green 100% 안정 확인 후 |
| 헬름 애드온 | blue 미반영. green/허브는 targetRevision(+apiVersion) 원복 → 재sync (ESO 는 CRD 전환 후 하향 어려움) |
| 허브 CP | 불가 — 유일 후진 blue/green |

---

## 실행 기록 & 이슈 (2026-09-28 — 스포크 완주, 허브는 익일)

각 단계 **실제 진행 1~2줄 + 겪은 이슈/해결**. (완주 후 PROGRESS 로 옮기고 이 문서 삭제)

**STEP 0 — auto-sync off (blue 동결)**
- 실제: 스포크 애드온 appset 17개 `automated` 블록 주석처리. gitops `scripts/toggle-spoke-autosync.sh` (disable/enable 토글).
- 이슈: ①대상만 vs 전체 → **전체**(selfHeal 가 딸려와 부분만 끄면 blue 안 얼음). ②삭제 아닌 **주석 토글**(파일별 prune 설정 원본 보존, 가역성). ③karpenter류 끝개행 없어 왕복 diff 어긋남 → 줄끝 보존 픽스.

**STEP 1 — 스포크 헬름 선행 상향**
- 실제: KEDA 2.21 / cert-manager v1.21 / ESO 2.11 `targetRevision` 변경. blue 는 sync 안 해 무영향.

**green 등록파일 (A2)**
- 실제: `clusters/spoke-demo-eks-02.yaml` = eks-01 복제 + name·SM키 치환 + 라벨 `dns-weight:"0"`.
- 이슈: apiVersion **v1beta1 유지 필수** — 허브 ESO 0.10 이 등록 ES 처리. v1 로 했으면 green 등록 자체가 깨짐.

**STEP 2 — green TF (eks-02)**
- 실제: `live/workload/eks-02/` eks-01 복제, cluster_name·k8s 1.35·addon 5종 1.35.
- 이슈: ①**backend key** 안 바꾸면 eks-01 state 덮어씀(치명) → eks-02 로. ②복사돼온 `.terraform/` 캐시가 eks-01 backend 가리킴 → 삭제(재init 유도).

**karpenter 하드코딩 (green sync 중 발견)**
- 이슈: values.yaml `clusterName`·`interruptionQueue`, ec2nodeclass SG태그·node role 이 `demo-eks-01` 박힘 → green 이 blue 리소스 찾음.
- 해결: **`{{.name}}` 템플릿화** — chart values→appset `valuesObject` 주입, node-pool 을 **Helm 차트로 전환**(templates/ + clusterName). ALB 패턴과 통일. (타 애드온은 이미 {{.name}}/pod-identity 라 OK)

**ESO apiVersion (green ESO sync 에러)**
- 이슈: green ESO 2.x 가 `v1beta1` ExternalSecret 거부.
- 해결: **스포크-처리분만 v1** (`platform/spoke/eso-resources` ClusterSecretStore, 앱 차트 ExternalSecret). 허브-처리분(허브 4개 + 등록 cluster Secret)은 v1beta1 유지 — **처리 주체 ESO 버전에 맞춤**.

**STEP 3 — green 온보딩·검증**
- 실제: appset 이 green child app 자동 생성 → wave 순 수동 sync → 전 애드온 Healthy, 앱(dev) 배포.
- 이슈: green 이 로컬 kubeconfig 에 없음 → `aws eks update-kubeconfig --name demo-eks-02 --alias demo-eks-02`.

**STEP 4 — 트래픽 커트오버 (Route53 weighted)**
- 실제: 골든차트 ingress 에 `set-identifier`(=클러스터명, appset)+`aws-weight`(=cluster 라벨 `demo.io/dns-weight`). blue100/green0 → green 10(canary) → 100, blue → 0. 실측: Route53 60회 green 10(≈weight 비율), green ALB 직접 30/30 성공, 최종 40/40 green.
- 이슈: ①처음 **delete-recreate 제안 = 다운타임 폭탄** → **weighted 로 정정**(무중단·canary·즉시롤백, AWS 블로그 표준). ②weight 가 클러스터별이라 values 공유 불가 → **cluster Secret 라벨**로. ③초기 **simple→weighted 전환**: blue frozen 이라 blue 쪽은 Route53 수동(change-batch)+blue external-dns 정지. green 은 declarative. ④**green weight=라벨(git)만** — Route53 직접 바꾸면 external-dns 가 어노테이션값으로 되돌림. **blue weight=Route53 수동만**(ed 정지+frozen). ⑤Record ID(=set-identifier)는 클러스터별 유일("app" 공용값 X). ⑥`policy=upsert-only` 필수(sync 면 다른 set-id 삭제).
- **thanos-sidecar.eks**: 하드코딩 공유 레코드 → green 실시간 메트릭 막힘(S3 과거·로그는 정상). 커트오버 시 **flip**(한방 전환). canary 관찰은 **로그**로(Next.js access 로그 안 찍혀 요청수 카운트 불가 — split 은 Route53 조회+green 직접타격으로 실측).

**STEP 5 — blue destroy**
- 실제: `scripts/spoke-teardown.sh demo-eks-01` = ingress삭제(LBC→ALB)→LB서비스삭제(→NLB)→ELB소멸대기→nodepool삭제(Karpenter노드종료)→tf destroy→Route53 blue레코드(SetIdentifier=demo-eks-01) 삭제.
- 이슈: ①**tf destroy 만으론 ALB/노드 고아** — 컨트롤러(LBC·Karpenter)가 만든 AWS 리소스는 클러스터 살아있을 때 finalizer 로 먼저 정리. ②`eks-stop.sh` 재사용 불가(single-spoke 가정: 허브 ArgoCD 전역 정지·ELB 전체 카운트) → **green-safe `spoke-teardown.sh` 신설**(클러스터 태그 필터). ③스크립트 버그: ELB 대기 `grep -c || echo 0` 가 "0\n0" → `|| true` 픽스.

**STEP 6 — 허브 in-place**: 익일 진행 (§6).

---

## 개선 백로그 (나중에)

**thanos-sidecar `additionalEndpoints` 자동화** — 현재 허브 Thanos Query 가 **스포크마다 엔드포인트 1줄 수동**(`platform/hub/thanos/values.yaml`). 불가피한 이유: per-cluster 이름(`thanos-sidecar-<cluster>`)이라 와일드카드 DNS 조회 불가 + 공유이름 다중 A 는 external-dns owner 충돌. **정상 비용**이고 policy-reporter `ui.clusters` 와 동일 패턴(스포크 추가 시 한 줄).
- 완전 자동화가 필요해지면(스포크 多):
  - **①** Thanos Query `--store.sd-files` + 클러스터 등록 훅/스크립트가 엔드포인트 파일 생성 (선언적 SD)
  - **②** 아키텍처 전환: sidecar fan-out → **Thanos Receive(remote_write)** — 스포크가 push 해서 허브 엔드포인트 목록 자체가 불필요. 단 허브 Receive 부하 = C6 에서 일부러 안 택한 트레이드오프. 되돌릴 이유 생길 때만.
- **현 판단**: 스포크 소수 → 수동 1줄 유지. 스포크 많아지면 ①.

**thanos-sidecar 구 레코드 정리**: 공유이름 `thanos-sidecar.eks`(per-cluster 전환 전 것)가 Route53 orphan 으로 남음 — green 재기동 후 수동 삭제(external-dns upsert-only 라 자동삭제 안 됨).
