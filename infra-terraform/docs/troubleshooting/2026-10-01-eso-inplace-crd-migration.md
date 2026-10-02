# 허브 ESO 0.10→2.11 in-place — CRD 가 안 올라와 컨트롤러 CrashLoop (2026-10-01)

**문제**: 허브 external-secrets 2.11 로 올린 뒤 컨트롤러 파드 CrashLoop — `no matches for kind "ExternalSecret" in version "external-secrets.io/v1"`. green(스포크)은 멀쩡.

**왜**: 컨트롤러만 2.11 이고 CRD 는 v1 이 안 올라옴. green 은 fresh 라 처음부터 v1, 허브는 in-place 라 기존 CRD 와 충돌. 3연속 벽:
- ① 기존 CRD `conversion=Webhook`(0.10 이 심음) 을 차트의 `None` 으로 덮을 때, SSA 가 기존 `webhook.clientConfig`(cert-controller 소유)를 못 지워 `strategy:None + webhookConfig = invalid` 로 apply 거부.
- ② `secretstores`/`clustersecretstores` CRD 283KB → client-side apply 의 `last-applied` annotation 256KB 초과 (`Too long`).
- ③ CRD v1 올린 뒤에도 매니페스트가 v1beta1 이라, 그걸 쓰는 앱(kps 등) 전체가 `parseableType ... v1beta1` comparison 에러로 Degraded (신 CRD 는 v1beta1 served 안 함).

**어떻게**:
- ① 기존 CRD conversion 수동 정리(백업 먼저): `kubectl patch crd <crd> --type=merge -p '{"spec":{"conversion":{"strategy":"None","webhook":null}}}'`
- ② ArgoCD sync 를 `ServerSideApply=true` 로. ⚠️ `--force` 와 server-side 동시 불가 → operation 에 `apply.force` 빼기
- ③ v1beta1 매니페스트 전수 전환(허브 ES 4개 + 등록 cluster secret) — ✅ gitops `95ac04c`
- 데이터: conversion None 이면 기존 객체 보존(ESO v1beta1↔v1 호환) — 안 날아감. ExternalSecret 전부 SecretSynced 유지 확인됨.
- 사전예방: CRD 보유 애드온은 현재↔목표 CRD 정적 비교 + `kubectl apply --dry-run=server` 로 거부 사전 재현 (in-place 업그레이드 체크리스트 참고). fresh 클러스터(green)가 있으면 그 CRD 가 목표 형태 정답지.
