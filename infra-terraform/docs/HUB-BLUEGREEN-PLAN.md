# 허브 blue/green — 전면 재생성 전략 (ArgoCD 포함)

> 2026-10-01 초안. 다음 허브 업그레이드(F4 1.35→1.36)부터 적용 후보.
> 철학: **허브는 가축이다.** 상태는 전부 밖에 있다 — 시크릿=SM, 메트릭=S3(Thanos), 로그=S3(Loki),
> 스포크 등록=SM+ESO. 새 허브는 "빈 클러스터 + 수동 3단계 + auto-sync"로 완전 재조립된다.
> 스포크 b/g(1.35, UPGRADE-PLAN-1.35)와 다른 점 = 허브는 **관제탑 자신의 이사**라서
> 트래픽 커트오버(weight) 대신 **관제권/수신권 커트오버**가 핵심이다.

## 왜 되는가 — 이사 안 해도 되는 것들

| 자산 | 위치 | green 에서 |
|---|---|---|
| 모든 시크릿 (SSO·deploy key·grafana admin·스포크 등록) | Secrets Manager | ESO 가 자동 재동기화 |
| 메트릭 장기보관 | S3 `demo-thanos-metrics` | store-gateway 가 그대로 서빙 |
| 로그 | S3 `demo-loki-logs` | 동일 |
| 스포크 워크로드/애드온 | 스포크 클러스터 | **무영향** — green ArgoCD 가 adopt (tracking id 동일, sync=no-op) |
| 플랫폼 전체 선언 | gitops repo | app-of-apps 재적용이 곧 복원 |

## 선언에서 새는 지점 6개 — 이게 작업의 전부

1. **gitops `platform/hub` 에 `demo-hub-01` 하드코딩 13곳** (5파일 + bootstrap-argocd.sh 등):
   karpenter values/ec2nodeclass(노드 role·discovery 태그), alloy cluster 라벨, loki, kps,
   ALB controller·external-dns `_apps`. → **사전 숙제 ①: 클러스터명 변수화** (허브는 app-of-apps 라
   appset `{{.name}}` 주입이 없음 — values 한 곳에 몰아서 전환 시 1커밋으로).
2. **스포크 trust**: `demo-eks-02` 의 argocd-spoke role 이 `demo-hub-01-argocd-mgmt` ARN 을 신뢰
   (`live/workload/eks-02` tfvars `hub_cluster_name_base`). → 스포크 tfvars 1줄 + apply 로 교체.
   교체 순간 blue ArgoCD 는 스포크 관리권 상실(의도) — 워크로드는 무영향.
3. **스포크 SG 인바운드**: `addons-sg.tf` 가 허브 cluster SG id 를 SSM(`/demo/eks/<허브명>`)에서
   읽어 10901(thanos)·8080(policy-reporter) 허용. → 2번과 같은 apply 에 같이 교체됨.
4. **DNS 레코드 소유권** (policy-reporter 404 사고의 정식 재연): `argocd/grafana/policy/loki.eks`
   레코드는 blue external-dns 소유(TXT). ingress 를 딴 클러스터로 옮겨도 레코드는 안 따라온다.
   → **blue external-dns scale 0 → 레코드+TXT 수동 삭제 → green external-dns 가 재생성**.
5. **Grafana PVC (persistence 2Gi)**: 수동 대시보드는 클러스터 로컬 EBS. → **사전 숙제 ②:
   남길 대시보드는 export 해서 git(sidecar provisioning)으로. 코드화 안 된 건 유실 수용.**
6. **Prometheus 로컬 3d / Receive 최근 ~2h**: S3 업로드 전 구간은 갭. 수용 (장기는 Thanos 가 보존).

## 순서

```
0. 사전 숙제: ① gitops 허브 클러스터명 변수화  ② Grafana 대시보드 코드화
   (이건 지금 해둬도 무해 — 해두면 b/g 는 "값 1개 바꾸는 일"이 된다)
1. green 스택: live/hub/eks-hub-01 복제 → eks-hub-02
   (cluster_name_base=hub-02 · backend key · 타겟 버전+애드온 5종. 폴더=클러스터=state 1:1)
   terraform apply → 빈 클러스터 (SSM /demo/eks/demo-hub-02 자동 발행)
2. green 부트스트랩 (수동 3단계 재연): bootstrap-argocd.sh(hub-02 인자) → app-of-apps-hub apply
   → apps root apply. ESO 기동 → SM 에서 스포크 등록 시크릿 동기화 → 스포크 자동 재등록
3. 스포크 재지향: eks-02 tfvars `hub_cluster_name_base = "hub-02"` → apply
   (trust + SG + SSM 참조 한 방에. 이 시점부터 관제권 = green)
4. green ArgoCD 에서 전 앱 Healthy 확인 — 스포크 앱은 adopt 라 diff 0 이어야 정상
5. DNS 커트오버: blue external-dns scale 0 → 허브 소유 레코드+TXT 삭제 → green 이 재생성
   → argocd/grafana/policy/loki URL 접속 검증 (스포크 소유 레코드는 불가침)
6. 관측 연속성: Grafana→Thanos 과거 조회(S3), 스포크 수집기가 green loki NLB 로 push 확인
7. blue 철거: blue ArgoCD 컨트롤러 정지 → ALB/NLB(ingress/svc) finalizer 정리 → tf destroy
   (spoke-teardown.sh 의 허브판 — 컨트롤러 살아있을 때 LB 먼저. 신규 스크립트 hub-teardown.sh)
8. 기록: PROGRESS 이전, eks-hub-01 폴더는 다음 b/g 의 green 틀로 유지 (01↔02 교대)
```

## 롤백

| 단계 | 방법 |
|---|---|
| 3 이전 | green tf destroy 만 — blue 는 아무것도 모름 |
| 3~5 | 스포크 tfvars 원복 apply + DNS 재삭제·blue external-dns 재기동 (양방향 동일 절차) |
| 7 이후 | 불가 — green 이 유일. 철거는 green 1주 안정 확인 후 |

## in-place 와 비교 (10/1 실전 기준)

| | in-place (이번에 함) | blue/green (이 문서) |
|---|---|---|
| CP 롤백 | 불가 | tf destroy 로 가능 (철거 전까지) |
| 소요 | ~30분 | 반나절 (부트스트랩+커트오버) |
| 리스크 | 노드 서지·애드온 동시교체가 라이브에서 | 라이브(blue)는 끝까지 무변경 |
| 부수효과 | Prometheus OOM 등 라이브 사고 | 관측 ~2h 갭, 수동 대시보드 유실(코드화 전) |
| 연습 가치 | 애드온/NG 롤링 관찰 | DR 리허설 그 자체 — "허브 전소 후 재건" 검증 |
