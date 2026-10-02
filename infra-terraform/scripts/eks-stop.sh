#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# eks-stop.sh — 비용 내리기 (한 방에, 허브·스포크 전략 다름)
#
#   허브(demo-hub-01)  : 노드·ALB·NLB 만 0, 컨트롤플레인 유지 (재구축 복잡 — ArgoCD 등)
#   스포크(demo-eks-02): 통째로 terraform destroy (컨트롤플레인까지 $73/mo 절약).
#     ※ 단일 스포크 전제. blue/green 로 스포크 교체 시 아래 SPOKE_CTX·SPOKE_STACK 만 갱신.
#                       스포크는 ArgoCD/부트스트랩 없어 재생성 시 허브가 자동 온보딩 → 안전.
#
#   남는 floor ≈ 허브 CP $73 + NAT $43 ≈ $116/mo (스포크 CP 까지 제거).
#
# ⚠️ 이 스크립트는 spoke 단계에서 `terraform destroy` 를 실행함(규칙상 운영자가 직접 실행).
# 실행:  ./scripts/eks-stop.sh        DRY_RUN=1 로 미리보기
# 복구:  ./scripts/eks-start.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
export AWS_PAGER="" # aws cli v2 자동 pager(less) 끔 — q 입력 대기 방지

TF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="ap-northeast-2"
HUB_CTX="arn:aws:eks:${REGION}:111111111111:cluster/demo-hub-01"
SPOKE_CTX="demo-eks-02"
SPOKE_STACK="live/workload/eks-02"
DRY_RUN="${DRY_RUN:-0}"

run() { echo "+ $*"; [[ "$DRY_RUN" == "1" ]] || "$@"; }
# LoadBalancer 타입 Service 만 삭제 (NLB 회수)
del_lb_svc() { local ctx="$1"
  [[ "$DRY_RUN" == "1" ]] && { echo "+ (dry) delete LoadBalancer services on $ctx"; return; }
  kubectl --context "$ctx" get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | while read -r ns svc; do [[ -n "$svc" ]] && kubectl --context "$ctx" -n "$ns" delete svc "$svc" --ignore-not-found; done
}

echo "══ EKS STOP — 허브: 노드/LB 0 (CP 유지) · 스포크: tf destroy (통째로) ══"
if [[ "$DRY_RUN" != "1" ]]; then
  read -rp "진행? (yes): " ok; [[ "$ok" == "yes" ]] || { echo "취소"; exit 1; }
fi

# 0) ArgoCD selfHeal 정지 (허브가 양쪽 관리 → 허브만)
echo "── 0) ArgoCD 컨트롤러 정지 ──"
run kubectl --context "$HUB_CTX" -n argocd scale statefulset/argocd-application-controller --replicas=0 || true
run kubectl --context "$HUB_CTX" -n argocd scale deploy/argocd-applicationset-controller --replicas=0 || true

# 1) 양쪽 ALB/NLB 회수 (컨트롤러 살아있을 때)
echo "── 1) Ingress·LoadBalancer Service 삭제 (허브+스포크) ──"
for ctx in "$HUB_CTX" "$SPOKE_CTX"; do
  run kubectl --context "$ctx" delete ingress --all --all-namespaces --ignore-not-found || true
  del_lb_svc "$ctx"
done
echo "  k8s-* LB 소멸 대기(최대 5분)…"
for i in $(seq 1 30); do
  LEFT=$(aws elbv2 describe-load-balancers --region "$REGION" --query "length(LoadBalancers[?starts_with(LoadBalancerName,'k8s-')])" --output text 2>/dev/null || echo "?")
  echo "    남은 k8s-* LB: $LEFT"; [[ "$LEFT" == "0" || "$DRY_RUN" == "1" ]] && break; sleep 10
done

# 2) 양쪽 Karpenter NodePool 삭제 + 노드 소멸 대기 (system NG 죽기 전에 Karpenter 가 정리 완료해야 함)
echo "── 2) Karpenter NodePool 삭제 + 노드 소멸 대기 ──"
for ctx in "$HUB_CTX" "$SPOKE_CTX"; do
  run kubectl --context "$ctx" delete nodepools.karpenter.sh --all --ignore-not-found --wait=false || true
done
for i in $(seq 1 30); do
  T=$(( $(kubectl --context "$HUB_CTX" get nodes -l karpenter.sh/nodepool --no-headers 2>/dev/null | wc -l) \
      + $(kubectl --context "$SPOKE_CTX" get nodes -l karpenter.sh/nodepool --no-headers 2>/dev/null | wc -l) ))
  echo "    남은 Karpenter 노드: $T"; [[ "$T" == "0" || "$DRY_RUN" == "1" ]] && break; sleep 10
done

# 3) 허브 매니지드 NG → 0 + 강제종료 (PDB 로 drain 막혀도 확실히 내림)
echo "── 3) [허브] 매니지드 노드그룹 0 + 인스턴스 강제종료 ──"
for ng in $(aws eks list-nodegroups --cluster-name demo-hub-01 --query "nodegroups[]" --output text 2>/dev/null); do
  run aws eks update-nodegroup-config --cluster-name demo-hub-01 --nodegroup-name "$ng" --scaling-config "minSize=0,maxSize=2,desiredSize=0"
  ASG=$(aws eks describe-nodegroup --cluster-name demo-hub-01 --nodegroup-name "$ng" --query "nodegroup.resources.autoScalingGroups[0].name" --output text 2>/dev/null)
  IDS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query "AutoScalingGroups[0].Instances[].InstanceId" --output text 2>/dev/null)
  [[ -n "$IDS" ]] && run aws ec2 terminate-instances --instance-ids $IDS >/dev/null || true
done

# 4) 스포크 통째로 terraform destroy (K8s 정리는 위 1·2 에서 끝남 → 고아 NLB/노드 없음)
echo "── 4) [스포크] terraform destroy  $SPOKE_STACK ──"
( cd "$TF_ROOT/$SPOKE_STACK"
  run terraform init -input=false >/dev/null
  run terraform destroy -auto-approve
)

echo "══ ✅ STOP 완료. 허브 노드·LB 0 (CP 유지) · 스포크 삭제됨. floor ≈ \$116/mo ══"
echo "   복구: ./scripts/eks-start.sh  (허브 올리고 스포크 재생성+자동 온보딩)"
