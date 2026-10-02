# 허브 Prometheus OOM — 업그레이드 노드 서지 (2026-10-01)

**문제**: 업그레이드 중 Grafana 에 허브 노드가 2대만 보임. 실체는 Prometheus OOMKilled
크래시루프 — 대시보드는 죽기 직전 데이터가 멈춰 보이던 것.

**왜**: 노드그룹 롤링 선증설(DEFAULT 전략)로 노드 2→5대 → 스크랩 타깃 급증 → limit 512Mi 초과.
재시작마다 WAL 리플레이가 메모리를 또 먹어 루프. 노드 회수 후 자가 회복했지만 운이었음.

**어떻게**:
- 대시보드가 이상하면 `kubectl get nodes` 로 실물부터 대조 — 화면 말고 수집기 본체 의심
- 기동 로그 깨끗한데 반복 사망 = `lastState.terminated` 확인 (OOM 은 앱 로그에 안 남음, exit 137)
- 픽스: kps values 메모리 512Mi→1Gi — ✅ 반영됨 (gitops `d05213c`)
- 서지 자체 축소: 노드그룹 `update_strategy = MINIMAL` — ✅ 반영됨 (10/1)
- 남은 숙제: Prometheus 가 죽으면 알람도 죽음 → deadman(Watchdog) 외부 수신 (백로그)
