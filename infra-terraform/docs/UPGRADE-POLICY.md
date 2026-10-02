# EKS 업그레이드 정책 (UPGRADE-POLICY)

> **불변 정책 문서.** 실행 계획은 여기서 생성하지 않는다 — 이 정책을 기준으로, 업그레이드 시점의 실측값을
> 반영해 `docs/UPGRADE-PLAN-<버전>.md` 를 따로 작성한다.
> ⚠️ 이 문서에 **버전 숫자를 박지 않는다** — 버전은 레포(variables.tf·appset)와 AWS API 가 기록하며, 여기 적는 순간 drift 소스가 된다.

## 1. 철학

- **클러스터 버전이 앵커.** 목표 CP 버전을 정하면 전체 애드온의 처분이 자동 도출된다.
- **관리형 애드온 = CP 와 세트 / 헬름 애드온 = 호환 게이트만.** CP 업그레이드 날 바뀌는 변수를 최소화한다 —
  헬름 애드온은 다음 k8s 와 **비호환일 때만 선행 업그레이드**하고, 호환이면 안 건드린다. 최신화는 별도 트랙(F2 방식, 한 번에 하나).
- **스포크 = blue/green, 허브 = in-place.** 스포크는 소모품·무상태 → 신규 클러스터(green)를 목표 버전으로 짓고 검증 → DNS 커트오버 → 헌 클러스터(blue) destroy. 허브는 상태 보유(ArgoCD·Thanos)라 blue/green 불가 → in-place. **트래픽 0 인 green 검증 → 커트오버 → 트래픽 0 인 허브 in-place** 순 (위험도 낮은 순).
- **버전 제어 = sync (appset 클러스터별 차등 불필요).** git 엔 목표 버전 하나만. **blue 는 sync 안 함 → 옛 버전 유지 / green 만 sync → 새 버전 fresh 설치.** → ESO 등 CRD 라이브 마이그레이션이 스포크엔 없다(green 은 목표 apiVersion 을 처음부터). 작업 창 동안 auto-sync 전부 off, 끝나면 원복.
- **마이너 +1 씩만.** CP 는 건너뛰기 불가가 원칙이자 스펙.

## 2. 인벤토리 (위치 포인터 — 버전은 실시간 조회)

### A. Terraform 소유 (CP + EKS 관리형 애드온 5종)
| 항목 | 위치 |
|---|---|
| CP 버전 (허브) | `live/hub/eks-hub-01/variables.tf` → `cluster_version` |
| CP 버전 (스포크) | `live/workload/eks-01/variables.tf` → `cluster_version` |
| 관리형 5종 (coredns·kube-proxy·vpc-cni·pod-identity·ebs-csi) | 위 두 파일의 `addon_versions` 블록 (허브 L48~, 스포크 L51~) |
| 실측 조회 | `aws eks describe-addon` / default·latest = `aws eks describe-addon-versions --kubernetes-version <목표>` |

### B. GitOps 소유 (헬름 애드온 — 호환 게이트 대상)
| 항목 | 위치 |
|---|---|
| 스포크 애드온 전체 | `platform/spoke/_appsets/*-appset.yaml` → `targetRevision` (karpenter 는 OCI repoURL) |
| 허브 애드온 전체 | `platform/hub/_apps/*.yaml` (+ argocd·karpenter 는 엄브렐라 차트 Chart.yaml) |
| 노드 AMI | Karpenter EC2NodeClass (Bottlerocket, SSM alias — CP 올리면 신규 노드가 자동으로 새 AMI) + 시스템 MNG (TF) |

### C. 커스텀 리소스 (버전 아님, 승급 시 확인)
- Kyverno CEL 정책(`platform/spoke/tenancy/`) — k8s VAP 모델이라 k8s 버전 API 변화 민감
- 골든 차트(`apps/demo-app/chart`) — preStop sleep 등 k8s 1.30+ 네이티브 기능 사용 중

## 3. 계획 생성 시 3분류 규칙

목표 CP 버전 입력 → 인벤토리 전체 스캔 → 각 항목을 분류:

1. **세트 승급 (관리형 5종)**: 타겟 = **목표 k8s 버전의 default** (latest 는 다음 회차). green TF 는 생성 시 이 값으로, 허브는 in-place apply. kube-proxy 는 CP 와 마이너 정합 **필수** — 뒤져 있으면 CP 승급 불가 게이트.
2. **선행 필수 (git 버전 상향)**: 목표 k8s 버전과 비호환인 헬름 애드온. green 이 fresh 로 먹고 허브는 in-place sync. 판정 근거 = 차트 `kubeVersion` 제약 + upstream 호환 매트릭스(Karpenter·ArgoCD·Kyverno 등은 공식 문서 웹 조사 필수).
3. **불변 (계획에서 명시적으로 '안 건드림' 기록)**: 목표 버전과 호환인 헬름 애드온 전부. 최신화 욕심은 별도 트랙으로.

## 4. 실행 순서 (모든 회차 공통)

```
0. auto-sync off + blue sync 금지.  aws eks list-insights (양 클러스터) — deprecated API 게이트
1. git 버전 상향 (헬름 애드온 targetRevision + 필요한 apiVersion) — 커밋만, blue 미반영
2. green(신규 스포크) TF @목표버전 생성 → 등록(cluster Secret) → green 만 sync (애드온·앱 fresh)
3. green 검증 (트래픽 0, §5)
4. DNS 커트오버 blue → green (external-dns 레코드 경합 정리) → 실서비스(www.eks) 확인
5. blue destroy (green 안정 후)
6. 허브 in-place: 애드온 sync → variables.tf (cluster_version + addon_versions 세트) → plan → diff → apply → 관찰(§5)
7. 노드 1.x 확인, auto-sync 원복, PROGRESS.md 기록
```

## 5. 관찰 게이트 (애드온별 검증)

| 대상 | 검증 |
|---|---|
| CP | `kubectl get nodes`(전부 Ready·버전), API 응답, ArgoCD 전 앱 Healthy |
| coredns | 내부/외부 nslookup 실측, Loki coredns 에러 0 |
| kube-proxy | Service 경유 통신 (파드→ClusterIP) |
| vpc-cni | 신규 파드 IP 할당(스케일 1회), aws-node 로그 |
| pod-identity | ESO 시크릿 sync·KEDA CloudWatch 폴링 지속 |
| ebs-csi | Prometheus/Loki PVC 마운트 유지, 신규 PVC 프로비저닝 |
| 헬름 애드온 | 각 컨트롤러 로그 + 핵심 기능 1개 실측 (예: Karpenter=노드 프로비저닝, KEDA=HPA 메트릭 수신) |

## 6. 스큐(skew) 규칙

- kube-proxy ≤ CP (같은 마이너 권장, 뒤지면 승급 전 정합)
- kubelet(노드) 은 CP-3 까지 허용되나 우리는 CP 승급 직후 노드 순환으로 정합
- 헬름 애드온은 각자 매트릭스 (계획 생성 시 조사)

## 7. 롤백 규칙

- **스포크 = blue/green 자체가 롤백**: 커트오버 후 문제 시 DNS 되돌림(blue 살아있는 동안). blue destroy 는 green 안정 확인 후.
- **헬름 애드온 = 가능**: blue 는 애초에 미반영(sync 안 함). green/허브는 targetRevision(+apiVersion) 원복 → 재sync. 단 ESO 등 CRD stored version 전환 후엔 하향 어려움 → 허브(트래픽 0)에서 먼저 겪는다.
- **허브 CP = 불가**: 유일한 후진 = blue/green — 스포크가 이미 목표 버전으로 서비스 중이니 최후 수단.
- 콘솔 수동 변경 금지 (TF drift) — 응급도 코드로

## 8. 계획 문서(PLAN) 산출 형식

`docs/UPGRADE-PLAN-<목표버전>.md`: ① 실측 현황표(전 인벤토리 현재 버전) ② 3분류 결과표(타겟 버전·근거 링크 포함)
③ 실행 체크리스트(수정 파일:라인, 명령 복붙 가능하게) ④ 게이트별 검증 명령 ⑤ 롤백 시나리오.
적용 완료된 PLAN 은 결과를 PROGRESS 로 옮기고 삭제(핸드오버 패턴).
