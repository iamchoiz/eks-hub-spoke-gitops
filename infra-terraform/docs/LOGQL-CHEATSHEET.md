# LogQL 치트시트 — 우리 스택 기준 (2026-09-27, 수집기 = Grafana Alloy)

> Grafana → Explore → datasource **Loki**. 우리 라벨: `cluster` `namespace` `app` `container` `role`
> (Alloy 가 붙임 — 이 5개 외엔 라벨이 아니라 "로그 내용"이라 필터 연산자로 거른다)

## 레벨 1 — 스트림 선택 (여기서 시작)

LogQL 의 모든 쿼리는 `{라벨=값}` 선택으로 시작한다. **라벨 = 색인** — 여기서 좁힐수록 빠르다.

```logql
{namespace="demo-app-dev"}            # dev 앱 전부
{app="demo-api"}                           # 특정 앱 (클러스터 무관)
{cluster="demo-eks-01", app="demo-web"}     # AND 는 콤마
{namespace=~"demo-app-.*"}            # =~ 정규식 (dev·prod 한번에)
{app!="demo-web", namespace="demo-app-dev"}  # != 제외
```

## 레벨 2 — 내용 필터 (grep 에 해당)

선택한 스트림에서 줄 단위로 거른다. **체이닝 가능** — 왼쪽부터 순서대로.

```logql
{app="demo-api"} |= "error"                # 포함 (대소문자 구분!)
{app="demo-api"} |~ "(?i)error|fail"       # 정규식 포함 — (?i) = 대소문자 무시
{app="demo-api"} != "healthz"              # 제외 (probe 소음 제거에 필수)
{app="demo-api"} |= "error" != "timeout"   # error 인데 timeout 은 아닌 것
```

## 레벨 3 — 파서 (구조화 로그 다루기)

Alloy 는 로그 줄을 **앱이 찍은 원문 그대로** 보냄 (래핑 없음). 앱이 JSON 로그를 찍으면 `| json` 으로 필드를 **추출 라벨**화해 다시 필터 가능.

```logql
{app="demo-api"} | json                            # 앱이 JSON 로그일 때 필드 펼치기
{app="demo-api"} | json | level="error"           # 추출한 필드로 필터
{app="demo-web"} | logfmt                          # key=value 형식 로그일 때
{app="demo-api"} | json | line_format "{{.msg}}"   # 특정 필드만 깔끔히 출력
```

> 평문 로그엔 파서 불필요 — 레벨 2 필터만으로 충분. `| pattern`(비정형 파싱)도 있는데 필요할 때 찾아보면 됨.

## 레벨 4 — 메트릭화 (로그 → 그래프)

로그 줄 수를 시계열로 바꾼다. **대시보드 패널·알림의 재료.**

```logql
count_over_time({app="demo-api"}[5m])                        # 5분 창 로그량
sum(rate({app="demo-api"} |= "error" [5m]))                  # 초당 에러율 ★
sum by (app) (rate({namespace="demo-app-prod"}[5m]))    # 앱별 로그량 비교
```

## 레벨 5 — 실전 조합 (우리가 실제 쓸 것들)

```logql
# canary 만 지켜보기 (배포 중) — role 라벨은 골든차트 canaryMetadata 가 부착
{app="demo-web", role="canary"}

# canary vs stable 에러율 비교 (대시보드 패널 2개로 나란히)
sum(rate({app="demo-web", role="canary"} |~ "(?i)error" [5m]))
sum(rate({app="demo-web", role="stable"} |~ "(?i)error" [5m]))

# admission 거부 추적 — ⚠️ deny 는 kyverno "로그"에 없다! 기록 위치가 두 갈래:
{cluster="demo-hub-01", namespace="argocd"} |= "denied"   # ① 거부당한 요청자(ArgoCD 컨트롤러) 로그
{cluster="demo-eks-01"} |= "PolicyViolation"              # ② k8s Event (alloy kubernetes_events 수집)
# ②의 정확한 스트림 라벨은 Label browser 에서 job 라벨 확인 (이벤트는 컨테이너 로그와 별도 스트림)

# 특정 시간대 장애 조사: 스트림 넓게 + 내용으로 좁히기
{namespace=~"demo-app-.*"} |~ "(?i)(error|exception|panic|fatal)" != "healthz"
```

## 습관·함정

- **라벨로 먼저 좁히고 내용 필터는 나중** — `{app="x"} |= "y"` 는 빠르고, 넓은 스트림에 정규식만 걸면 느리다
- **고카디널리티 값(요청ID·IP 등)을 라벨로 만들지 말 것** — Loki 성능의 제1원칙 (그래서 fluent-bit 에 auto_kubernetes_labels 끔)
- 시간 범위(우상단)가 기본 1h — "로그가 없어요"의 8할은 시간 범위
- **Live 버튼** = kubectl logs -f 웹판. **Label browser** = 쿼리 몰라도 클릭 조합
- Explore 에서 만든 쿼리는 그대로 대시보드 패널로 저장 가능 (Add to dashboard)

## 연습 과제 (감 잡기용 — 순서대로)

1. `{namespace="demo-app-dev"}` 치고 Live 켠 뒤 https://www.eks.example.com 새로고침 → api 로그 흘러오나
2. `{app="demo-api"}` — api 로그 원문 확인 (JSON 으로 찍는 앱이면 `| json` 도 시도)
3. `{namespace="kyverno"} |= "denied"` — 지난 admission 거부 흔적 찾기 (시간범위 6h 로)
4. `sum by (app) (rate({cluster="demo-eks-01"}[5m]))` — 클러스터에서 제일 수다스러운 앱 찾기
5. web canary 배포 한 번 돌리면서 `{app="demo-web", role="canary"}` Live — role 라벨 실전 확인
