#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# eks-start.sh — eks-stop 복구 (한 방에)
#   허브 : 매니지드 NG 원복 + ArgoCD 원복 → selfHeal 로 애드온/LB 재생성
#   스포크: terraform apply 로 클러스터 재생성 → 허브 ArgoCD 가 appset+ESO 로 자동 온보딩
#   비자동싱크 앱(karpenter-node-pool 등)은 명시적 sync.
#
# ⚠️ spoke 단계에서 `terraform apply` 실행(규칙상 운영자가 직접).
# 실행:  ./scripts/eks-start.sh        DRY_RUN=1 로 미리보기
# 소요:  ~20~25분 (스포크 EKS 생성이 대부분)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export AWS_PAGER="" # aws cli v2 자동 pager(less) 끔 — q 입력 대기 방지

TF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="ap-northeast-2"
HUB_CTX="arn:aws:eks:${REGION}:111111111111:cluster/demo-hub-01"
# 단일 스포크 전제. blue/green 로 교체 시 이 두 줄만 갱신.
SPOKE_CLUSTER="demo-eks-02"
SPOKE_STACK="live/workload/eks-02"
NG_MIN=1; NG_DES=1; NG_MAX=2
DRY_RUN="${DRY_RUN:-0}"

run() { echo "+ $*"; [[ "$DRY_RUN" == "1" ]] || "$@"; }

# selfHeal(automated) 없는 앱만 명시적 sync — stop 때 지운 리소스(NodePool 등) 복구
sync_nonauto() {
  [[ "$DRY_RUN" == "1" ]] && { echo "+ (dry) sync non-automated apps"; return; }
  local apps
  apps=$(kubectl --context "$HUB_CTX" -n argocd get applications -o json 2>/dev/null \
    | python3 -c "import sys,json;print(' '.join(a['metadata']['name'] for a in json.load(sys.stdin)['items'] if not a['spec'].get('syncPolicy',{}).get('automated')))")
  for app in $apps; do
    echo "  sync $app"
    kubectl --context "$HUB_CTX" -n argocd patch application "$app" --type merge \
      -p '{"operation":{"sync":{"syncStrategy":{"apply":{}}}}}' >/dev/null 2>&1 || true
  done
}

# apply 가 리소스 생성 중 끊기면(tf 타임아웃 등) AWS 엔 생겼는데 state 엔 없어 다음 apply 가
# "already exists"(409) 로 실패. → AWS 에 있고 state 엔 없는 고아를 import 해서 이어가게 함(멱등).
reconcile_orphan() {
  local addr="$1" id="$2"; shift 2
  [[ "$DRY_RUN" == "1" ]] && { echo "+ (dry) reconcile $addr"; return; }
  if "$@" >/dev/null 2>&1 && ! terraform state list 2>/dev/null | grep -qx "$addr"; then
    echo "  ⟳ 고아 감지 → terraform import $addr ($id)"
    terraform import "$addr" "$id" || true
  fi
}

# 1) 허브 매니지드 NG 원복 + Ready 대기
echo "── 1) [허브] 매니지드 노드그룹 원복 (min=$NG_MIN,desired=$NG_DES,max=$NG_MAX) ──"
for ng in $(aws eks list-nodegroups --cluster-name demo-hub-01 --query "nodegroups[]" --output text 2>/dev/null); do
  run aws eks update-nodegroup-config --cluster-name demo-hub-01 --nodegroup-name "$ng" --scaling-config "minSize=${NG_MIN},maxSize=${NG_MAX},desiredSize=${NG_DES}"
done
echo "  허브 시스템 노드 Ready 대기(최대 5분)…"
for i in $(seq 1 30); do
  N=$(kubectl --context "$HUB_CTX" get nodes --no-headers 2>/dev/null | awk '$2=="Ready"{c++} END{print c+0}')
  echo "    허브 Ready 노드: $N"; { [[ "$N" -ge 1 ]] || [[ "$DRY_RUN" == "1" ]]; } && break; sleep 10
done

# 2) 허브 ArgoCD 원복
echo "── 2) [허브] ArgoCD 컨트롤러 원복 ──"
run kubectl --context "$HUB_CTX" -n argocd scale statefulset/argocd-application-controller --replicas=1
run kubectl --context "$HUB_CTX" -n argocd scale deploy/argocd-applicationset-controller --replicas=1
echo "  application-controller 기동 대기(20s)…"; [[ "$DRY_RUN" == "1" ]] || sleep 20

# 3) 허브 비자동싱크 앱 sync (karpenter-node-pool 허브 → platform 노드)
echo "── 3) [허브] 비자동싱크 앱 sync ──"
sync_nonauto

# 4) 스포크 terraform apply (재생성) — 허브 ArgoCD 가 이미 떠 있어야 온보딩됨(위에서 올림)
echo "── 4) [스포크] terraform apply  $SPOKE_STACK ──"
( cd "$TF_ROOT/$SPOKE_STACK"
  run terraform init -input=false >/dev/null
  # 이전 apply 가 클러스터/NG 생성 중 끊겼으면(tf 타임아웃) 고아를 import 로 흡수 → 이어서 진행
  reconcile_orphan "module.eks.aws_eks_cluster.this" "$SPOKE_CLUSTER" \
    aws eks describe-cluster --name "$SPOKE_CLUSTER"
  reconcile_orphan "module.eks.aws_eks_node_group.system" "$SPOKE_CLUSTER:system" \
    aws eks describe-nodegroup --cluster-name "$SPOKE_CLUSTER" --nodegroup-name system
  run terraform apply -auto-approve
)
run aws eks update-kubeconfig --region "$REGION" --name "$SPOKE_CLUSTER" --alias "$SPOKE_CLUSTER" || true

# 5) 스포크 온보딩 대기(ESO→cluster Secret→appset 앱 생성) → 스포크 비자동싱크 앱 sync
echo "── 5) [스포크] 온보딩 대기 후 비자동싱크 앱 sync ──"
if [[ "$DRY_RUN" != "1" ]]; then
  for i in $(seq 1 30); do
    HAS=$(kubectl --context "$HUB_CTX" -n argocd get applications --no-headers 2>/dev/null | grep -c "$SPOKE_CLUSTER" || true)
    echo "    스포크 앱 생성됨: $HAS"; [[ "$HAS" -ge 1 ]] && break; sleep 15
  done
  sleep 20  # appset 이 앱들 다 생성할 여유
fi
sync_nonauto

echo "══ ✅ START 완료. 허브 재싱크 + 스포크 재생성/온보딩 진행 중 (~10분 내 안정화) ══"
echo "   확인: kubectl --context $HUB_CTX -n argocd get applications | grep -v Synced.*Healthy"
echo "        kubectl --context $SPOKE_CLUSTER get nodes"
echo "        kubectl --context $SPOKE_CLUSTER get pods -n demo-app-dev   # 워크로드 앱도 appset 자동 온보딩 (루트 재apply 불필요)"
echo "        curl -sk -o /dev/null -w '%{http_code}\n' https://www.eks.example.com   # ALB+DNS(weighted) 재생성 후 (수 분 소요)"
