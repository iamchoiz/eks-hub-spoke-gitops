#!/usr/bin/env bash
# ArgoCD 설치 (멱등). 이 레포(gitops) 안에서 실행 — 로컬 chart 로 설치하니 재clone 불필요.
# 전제: EKS 클러스터 존재, deploy key 가 Secrets Manager(demo/argocd/gitops-deploy-key)에 있음.
# 사용:  gitops 레포 clone 후 →  ./platform/hub/argocd/install-argocd.sh
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"

REGION=ap-northeast-2
REPO=git@github.com:your-org/eks-hub-spoke-gitops.git
KEY=/tmp/gitops_key
trap 'rm -f "$KEY"' EXIT

HERE="$(cd "$(dirname "$0")" && pwd)"
CHART="$HERE" # 스크립트가 chart 와 같은 폴더에 있다 (진실원천)

aws eks update-kubeconfig --name demo-hub-01 --region "$REGION"

# 설치 — 로컬 umbrella chart (Chart.yaml 의 버전이 진실원천)
helm dependency update "$CHART"
helm upgrade --install argocd "$CHART" -n argocd --create-namespace --wait --timeout 10m

# ArgoCD 가 gitops 를 읽을 repo Secret (ESO 붙기 전 임시 — B5 이후 ESO 로 이관)
aws secretsmanager get-secret-value --secret-id demo/argocd/gitops-deploy-key \
  --query SecretString --output text --region "$REGION" > "$KEY" && chmod 600 "$KEY"
kubectl -n argocd create secret generic gitops-repo \
  --from-literal=type=git --from-literal=url="$REPO" \
  --from-file=sshPrivateKey="$KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret gitops-repo argocd.argoproj.io/secret-type=repository --overwrite

echo ""
echo "✓ 완료"
echo "  접속:  kubectl -n argocd port-forward svc/argocd-server 8080:80"
echo "  비번:  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d ; echo"
