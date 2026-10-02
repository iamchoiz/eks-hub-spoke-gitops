#!/usr/bin/env bash
# 스포크 클러스터 완전 자동 철거 — blue/green 커트오버 후 구(舊) 스포크 제거용.
#
# 왜 이 순서인가: ALB/NLB(LBC 소유)·Karpenter 노드는 TF 가 아니라 클러스터 안 컨트롤러가 만든다.
#   클러스터부터 tf destroy 하면 컨트롤러가 죽어 finalizer 를 못 돌려 AWS 리소스 고아(과금 지속).
#   → 컨트롤러 살아있을 때 리소스 먼저 삭제 → 컨트롤러가 AWS 것 정리 → 그다음 tf destroy.
#
# green-safe: 인자로 받은 스포크 1개만. 허브·다른 스포크는 안 건드림(ALB 는 클러스터 태그 필터).
# 전제: 대상 스포크 앱 auto-sync/selfHeal off (gitops toggle-spoke-autosync.sh disable) — 안 그러면 되살아남.
#
# 사용:
#   DRY_RUN=1 ./spoke-teardown.sh demo-eks-01           # 미리보기 (아무것도 안 지움)
#   DRY_RUN=0 ./spoke-teardown.sh demo-eks-01           # 전부 자동 실행 (kubectl 정리 → tf destroy → Route53)
#   인자: $1 = 클러스터 이름(= kube context = elbv2.k8s.aws/cluster 태그). context 다르면 CTX=... 로 오버라이드.
set -uo pipefail

CLUSTER="${1:?사용법: spoke-teardown.sh <cluster-name>  예) demo-eks-01}"
CTX="${CTX:-$CLUSTER}"
REGION="${REGION:-ap-northeast-2}"
DRY_RUN="${DRY_RUN:-1}"
ZONE_DOMAIN="${ZONE_DOMAIN:-eks.example.com}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK="${STACK:-$ROOT/live/workload/${CLUSTER#demo-}}"   # demo-eks-01 → live/workload/eks-01
export PATH="$HOME/.local/bin:$PATH"                    # terraform 1.16 (PROGRESS §3)

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
run() { echo "+ $*"; [[ "$DRY_RUN" == "1" ]] || eval "$@"; }

spoke_lbs() {  # 이 클러스터 소유 ALB/NLB ARN (태그 필터)
  aws elbv2 describe-load-balancers --region "$REGION" \
    --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null | tr '\t' '\n' | while read -r arn; do
    [[ -z "$arn" ]] && continue
    local hit; hit=$(aws elbv2 describe-tags --resource-arns "$arn" --region "$REGION" \
      --query "TagDescriptions[0].Tags[?Key=='elbv2.k8s.aws/cluster' && Value=='$CLUSTER'].Value | [0]" --output text 2>/dev/null)
    [[ "$hit" == "$CLUSTER" ]] && echo "$arn"
  done
}

wait0() {  # wait0 <설명> <카운트명령>
  local desc="$1" cmd="$2" n
  [[ "$DRY_RUN" == "1" ]] && { echo "  (dry) '$desc' 0 될 때까지 대기"; return; }
  for _ in $(seq 1 90); do
    n=$(eval "$cmd" 2>/dev/null || echo "?"); echo "  $desc: ${n:-?}"
    [[ "$n" == "0" ]] && return 0; sleep 10
  done; echo "  ⚠️ '$desc' 안 빠짐 — 수동 확인"; return 1
}

# ── 프리플라이트 ──
say "스포크 철거: cluster=$CLUSTER ctx=$CTX stack=$STACK  (DRY_RUN=$DRY_RUN)"
kubectl --context "$CTX" get nodes >/dev/null 2>&1 || { echo "❌ context '$CTX' 접속 불가"; exit 1; }
kubectl --context "$CTX" get ingress -A --no-headers 2>/dev/null | wc -l | xargs echo "  ingress:"
kubectl --context "$CTX" get nodes -l karpenter.sh/nodepool --no-headers 2>/dev/null | wc -l | xargs echo "  karpenter 노드:"
if [[ "$DRY_RUN" != "1" ]]; then
  read -r -p $'\n⚠️  '"$CLUSTER"$' 전체 삭제(되돌릴 수 없음). 클러스터명 다시 입력: ' a
  [[ "$a" == "$CLUSTER" ]] || { echo "불일치 — 중단"; exit 1; }
fi

# ── 1) ingress 삭제 → LBC 가 ALB/TG/SG룰 정리 ──
say "1) ingress 삭제 (LBC → ALB 정리)"
run "kubectl --context '$CTX' delete ingress --all --all-namespaces --ignore-not-found"

# ── 2) LoadBalancer 서비스 삭제 → NLB 정리 ──
say "2) LoadBalancer 서비스 삭제 (→ NLB)"
kubectl --context "$CTX" get svc -A \
  -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
  | while read -r ns svc; do [[ -n "$svc" ]] && run "kubectl --context '$CTX' -n '$ns' delete svc '$svc' --ignore-not-found"; done

# ── 3) 이 클러스터 ALB/NLB 소멸 대기 ──
say "3) ALB/NLB 소멸 대기 (태그 필터 — 다른 스포크 제외)"
wait0 "$CLUSTER ELB 수" "spoke_lbs | grep -c . || true"   # grep -c 는 0 일 때 exit1 → || true 로 '0' 만 반환

# ── 4) nodepool 삭제 → Karpenter 노드 종료 ──
say "4) nodepool 삭제 → Karpenter 노드 종료"
run "kubectl --context '$CTX' delete nodepools.karpenter.sh --all --ignore-not-found --wait=false"
wait0 "karpenter 노드 수" "kubectl --context '$CTX' get nodes -l karpenter.sh/nodepool --no-headers 2>/dev/null | wc -l | tr -d ' '"

# ── 5) terraform destroy (AWS 리소스 정리됐으니 고아 없음) ──
say "5) terraform destroy  $STACK"
if [[ "$DRY_RUN" == "1" ]]; then echo "+ (dry) cd $STACK && terraform destroy -auto-approve";
else ( cd "$STACK" && terraform init -input=false >/dev/null && terraform destroy -auto-approve ); fi

# ── 6) Route53 잔여 레코드 삭제 (이 클러스터 SetIdentifier — external-dns 못 지움) ──
say "6) Route53 weighted 레코드 삭제 (SetIdentifier=$CLUSTER)"
ZID=$(aws route53 list-hosted-zones-by-name --dns-name "$ZONE_DOMAIN" --region "$REGION" \
  --query "HostedZones[?Name=='${ZONE_DOMAIN}.'].Id | [0]" --output text 2>/dev/null | sed 's#/hostedzone/##')
if [[ -n "${ZID:-}" && "$ZID" != "None" ]]; then
  aws route53 list-resource-record-sets --hosted-zone-id "$ZID" \
    --query "ResourceRecordSets[?SetIdentifier=='$CLUSTER']" --output json > /tmp/rr-$CLUSTER.json 2>/dev/null
  cnt=$(python3 -c "import json;print(len(json.load(open('/tmp/rr-$CLUSTER.json'))))" 2>/dev/null || echo 0)
  echo "  SetIdentifier=$CLUSTER 레코드 $cnt 개"
  if [[ "$cnt" != "0" ]]; then
    python3 -c "import json;print(json.dumps({'Changes':[{'Action':'DELETE','ResourceRecordSet':r} for r in json.load(open('/tmp/rr-$CLUSTER.json'))]}))" > /tmp/rr-del-$CLUSTER.json
    run "aws route53 change-resource-record-sets --hosted-zone-id '$ZID' --change-batch file:///tmp/rr-del-$CLUSTER.json"
  fi
else echo "  ⚠️ 존 못 찾음($ZONE_DOMAIN) — Route53 수동 확인"; fi

# ── 7) gitops 등록 해제 (commit/push 는 규칙상 운영 결정) ──
say "7) 남은 수동: gitops 등록 해제 (규칙 = 운영자가 commit/push)"
echo "  clusters/spoke-$CLUSTER.yaml 삭제 → commit/push → 허브에서 상위 앱 sync"
echo "  (선택) thanos-sidecar 등 이 클러스터 소유 내부레코드 잔재 Route53 확인"
say "완료: $CLUSTER AWS 리소스 철거됨."
