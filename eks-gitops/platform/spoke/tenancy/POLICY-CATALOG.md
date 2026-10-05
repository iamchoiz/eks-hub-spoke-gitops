# Kyverno 정책 카탈로그 (권장 정책 + 고도화 가이드)

> EKS/멀티테넌시/GitOps 환경 기준 Kyverno admission 정책 레퍼런스.
> 출처: [Kyverno Policy Library](https://kyverno.io/policies/), [kyverno/policies](https://github.com/kyverno/policies), Pod Security Standards, [Managing Pod Security on EKS with Kyverno (AWS)](https://aws.amazon.com/blogs/containers/managing-pod-security-on-amazon-eks-with-kyverno/).
> 롤아웃 원칙: **Audit + background 로 시작 → PolicyReport 로 FAIL 0 확인 → Enforce 승격** (우리 C5 절차). 플랫폼 ns 제외목록 재사용.

---

## 0. 현재 적용 중인 정책 (2026-10 기준)

`platform/spoke/tenancy/validating-standards.yaml` — 전부 Pod 대상, 플랫폼 ns 제외.

- **require-resource-requests** 🔴 Deny — 모든 컨테이너 `resources.requests.cpu+memory` 필수.
  - 왜: requests 없으면 스케줄러가 노드 용량 계산 불가 → 과밀·축출. QoS `BestEffort` 로 떨어져 메모리 압박 시 최우선 종료. Karpenter 노드 프로비저닝 판단도 requests 기반.
- **disallow-latest-tag** 🔴 Deny — `:latest` 금지, 명시 태그/digest 필수.
  - 왜: latest 는 가리키는 이미지가 변해 재현·롤백 불가. 노드 캐시 탓 "배포했는데 안 바뀜" 사고.
- **require-env-label** 🔴 Deny — `labels.env ∈ {prod,nonprod}` 필수.
  - 왜(커스텀): 스포크 NodePool taint(`env=prod/nonprod`) 매칭·테넌시 격리·관측 필터의 기반.
- **require-kst-timezone** 🟡 Audit — 컨테이너 `env TZ=Asia/Seoul` 필수.
  - 왜(커스텀): 자사 전 서비스 KST 표준의 감시자. 골든 차트가 자동 주입. upstream 데모 위반 가능해 Audit 유지 중.

**공백**: 보안(Pod Security) 0 · 공급망 0 · RBAC 0 · 네트워킹 0. 아래가 그 공백을 메우는 표준 정책.

---

## 1. Pod Security Standards — Baseline (권한상승 차단, 최우선)

- **disallow-privileged-containers** (Enforce) — `privileged: true` 차단. 특권 컨테이너=호스트 root 수준, 뚫리면 노드 전체 탈취.
- **disallow-host-namespaces** (Enforce) — `hostPID/hostIPC/hostNetwork` 차단. 호스트 프로세스·네트워크 접근 → IMDS(노드 IAM) 탈취·격리 우회.
- **disallow-host-path** (Enforce) — `hostPath` 볼륨 차단. `docker.sock`·kubelet 인증서 등 호스트 파일 접근 → 노드 탈출.
- **disallow-host-ports** (Enforce) — `hostPort` 차단. Service 우회, 노드 네트워크 직접 노출, 포트 충돌.
- **disallow-capabilities** (Enforce) — `SYS_ADMIN`·`NET_ADMIN` 등 위험 capability 추가 차단. 커널 권한 → 컨테이너 브레이크아웃.
- **restrict-seccomp** (Enforce) — `seccompProfile.type: Unconfined` 차단. 전 syscall 허용=커널 공격면 확대.
- **restrict-apparmor-profiles** (Enforce) — `unconfined` AppArmor 차단. syscall 제한 해제 방지.
- **disallow-proc-mount / restrict-sysctls / disallow-selinux** (Enforce) — 호스트 커널 인터페이스 노출·위험 sysctl·MAC 우회 차단.

## 2. Pod Security Standards — Restricted (강한 하드닝, audit 충분히)

- **require-run-as-nonroot** (Enforce/audit 먼저) — root(UID 0) 실행 금지. 컨테이너 내 root=대부분 탈출 체인의 시작점.
- **disallow-privilege-escalation** (Enforce) — `allowPrivilegeEscalation: false` 강제. setuid 로 부모보다 높은 권한 획득 차단.
- **require-drop-all-capabilities** (Enforce/audit 먼저) — `capabilities.drop: ["ALL"]`, 추가는 `NET_BIND_SERVICE` 만. 커널 capability 최소권한.
- **restrict-volume-types** (Enforce/audit 먼저) — configMap/secret/emptyDir/projected/PVC 만 허용, hostPath 등 차단.
- **restrict-seccomp-strict** (Enforce/audit 먼저) — `RuntimeDefault`/`Localhost` 강제. 모든 컨테이너에 syscall 필터 보장.

> 💡 1·2 를 정책 수십 개로 쓰는 대신 Kyverno `validate.podSecurity: {level: restricted, version: latest}` 한 룰로 PSS 전체 추적 가능(upstream 자동 반영). 모던 방식 권장.

## 3. Best Practices (안정성·운영 위생)

- **require-requests-limits** (Enforce/audit) — requests(이미 있음) + **limits** 강제. 없으면 noisy 파드가 노드 OOM·연쇄 축출 유발.
- **require-probes** (Audit→Enforce) — liveness/readiness(+startup) 필수. 없으면 죽은 파드에 트래픽 계속, hung 파드 재시작 안 됨.
- **disallow-default-namespace** (Enforce) — default ns 워크로드 차단. 쿼터·정책·격리 없는 ns → 거버넌스 구멍.
- **require-labels** (Audit→Enforce) — app/team/owner 등 표준 라벨. 비용배분·오너십·장애 triage.
- **restrict-image-registries** (Enforce) — 승인 레지스트리(우리 ECR·신뢰 미러)만. 타이포스쿼팅·비신뢰 이미지 차단 = 공급망 1차 방어.
- **require-ro-rootfs** (Audit→Enforce) — `readOnlyRootFilesystem: true`. 루트FS 불변 → 멀웨어 바이너리 기록 차단.
- **require/add-pod-disruption-budget** (Audit) — Deployment 에 PDB. 노드 드레인·업그레이드 때 동시 축출 상한 → 가용성 보호.
- **disallow-empty-ingress-host** (Audit) — Ingress host 명시 필수. 빈 host=catch-all 라우트로 트래픽 하이재킹.

## 4. 공급망 (Supply Chain)

- **verify-image (cosign, keyed/keyless)** (Enforce) — 서명 검증. 내 파이프라인이 만든 이미지만 실행, 레지스트리 변조 차단. keyless 는 CI OIDC 신원(예: GitHub Actions)과 바인딩.
- **require-image-digest** (Audit→Enforce) — 태그 대신 `@sha256` 고정. 불변, 검증한 바이트 그대로 실행.
- **check-image-attestations (SBOM/SLSA/vuln)** (Audit→Enforce) — 서명된 증명 요구. SBOM 없거나 치명 CVE 있는 이미지 차단.
- **mutate-image-to-digest** (Mutate) — 태그를 admission 때 digest 로 자동 치환. 개발자가 손으로 digest 안 써도 됨.

> 이미지 검증은 레지스트리/Rekor 로의 네트워크 접근 + admission 컨트롤러 도달성 필요. ECR IAM(Pod Identity)·`failurePolicy` 설계 동반.

## 5. RBAC 하드닝 (RBAC 객체도 admission 검사)

- **restrict-binding-clusteradmin** (Enforce) — 빌트인 `cluster-admin` 바인딩 차단. 갓모드 직통 경로.
- **restrict-wildcard-verbs / restrict-wildcard-resources** (Enforce/audit) — `verbs:["*"]`·`resources:["*"]` 차단. 과잉권한·최소권한 위반, secret/CRD 포함 전체 접근.
- **restrict-binding-system-groups** (Enforce) — `system:masters`·`anonymous`·`unauthenticated` 바인딩 차단.
- **restrict-escalation-verbs-roles** (Enforce) — `escalate/bind/impersonate` 차단. 스스로 권한 올리는 primitive.
- **restrict-automount-sa-token** (Audit→Enforce) — 불필요한 SA 토큰 자동마운트 차단. 침입자용 준비된 자격증명 제거.

## 6. 네트워킹

- **generate default-deny NetworkPolicy** (Generate) — 새 ns 마다 default-deny 생성. K8s 기본 allow-all → 제로트러스트 east-west.
- **disallow-service-type-nodeport** (Enforce) — NodePort 차단. 모든 노드 포트 오픈, 인그레스·WAF 우회.
- **restrict-loadbalancer** (Audit→Enforce) — `type: LoadBalancer` 게이트. LB 마다 ELB/NLB 생성(비용+공개노출).
- **restrict-ingress-host / restrict-external-ips** (Enforce) — 승인 도메인만 허용·`externalIPs` 차단. 호스트 하이재킹·MITM 벡터 방지.

## 7. 멀티테넌시 (generate 중심)

- **generate ResourceQuota+LimitRange** (Generate, synchronize) — 테넌트 ns 마다 쿼터·기본 limits 보장(우리 GeneratingPolicy 이미 사용). uncapped ns 제거.
- **generate NetworkPolicy** (Generate) — 테넌트 간 기본 격리.
- **require-ns-labels (tenant/owner)** (Enforce) — ns 라벨 강제. quota/netpol/RBAC 생성과 chargeback 의 키.
- **sync pull-secret / CA bundle** (Generate, clone+synchronize) — 공유 시크릿 자동 배포·소스 변경 시 동기화.

---

## 8. Kyverno 고도화 — Validate 너머

- **Mutate** — admission 때 리소스 수정. 거부 대신 **안전 기본값 주입**(securityContext 기본값, 라벨, limits, 사이드카, `automount:false`, 이미지→digest). 개발자 안 깨고 플랫폼이 고침. `mutateExisting` 은 기존 리소스도 트리거로 패치.
- **Generate** — 트리거 시 하위 리소스 자동 생성(NetworkPolicy·Quota·ConfigMap·RoleBinding). `synchronize:true` 면 지워도 복구, `clone` 은 소스에서 복제·동기화. 멀티테넌시 자동화의 토대.
- **ImageVerify (ImageValidatingPolicy)** — cosign/notary 서명·SBOM/SLSA 증명 검증. 클러스터 밖(레지스트리·Rekor)과 통신하는 유일한 타입.
- **Cleanup (CleanupPolicy / TTL)** — 스케줄·조건으로 리소스 삭제. 완료 Job, PR 프리뷰 ns, 만료 리소스 GC. CronJob 불필요.
- **PolicyException** — 특정 리소스를 특정 룰에서 선언적 예외. CNI·CSI·모니터링 에이전트가 진짜 hostPath/privileged 필요할 때, 정책 약화 대신 GitOps 로 추적되는 scoped 예외. `enableException:true` + 예외 보유 ns 제한 권장.
- **Background scanning** (`background:true`) — 기존 리소스 주기 재평가 → PolicyReport/ClusterPolicyReport. admission 때 못 잡은 기존 위반 지속 가시화(우리 policy-reporter 소스). AdmissionReview 전용 데이터(요청 user 등) 의존 룰은 평가 불가.
- **Autogen** — Pod 룰을 Deployment/STS/DS/Job/CronJob/ReplicaSet 로 자동 확장. 룰 1개만 쓰면 전 워크로드 타입 커버. `pod-policies.kyverno.io/autogen-controllers` 로 제어.

> ⚠ 현재 정책은 `resources: ["pods"]` 로 Pod 만 매칭 → Deployment apply 시점엔 에러 안 뜨고 ReplicaSet 단계에서 막혀 UX 나쁨. autogen 또는 매칭에 controller 추가 고려.

---

## 9. 도입 우선순위 (우리 환경)

1. **보안 기본**: PSS Baseline(privileged·hostPath·host-ns·capabilities) + restrict-image-registries(ECR만)
2. **안정성 보강**: require-limits · require-probes · disallow-default-namespace
3. **하드닝**: PSS Restricted(run-as-nonroot·drop-all·ro-rootfs) — audit 충분히
4. **RBAC·네트워킹**: clusteradmin 바인딩·wildcard 금지 + NodePort 금지 · default-deny netpol
5. **공급망(가장 까다로움)**: 이미지 서명 검증(cosign) — 파이프라인 OIDC 수반

전부 Audit+background → FAIL 0 → Enforce. 플랫폼 ns 제외목록 재사용.

**EKS 주의**: 보안 enforce 정책은 `failurePolicy: Fail`(closed) 로 하되, webhook SPOF 안 되게 Kyverno admission replica 2+ HA 필수. CNI·EBS CSI·CloudWatch/Fluent Bit 등 노드 에이전트는 hostPath/privileged 정당 → `exclude`/PolicyException.
