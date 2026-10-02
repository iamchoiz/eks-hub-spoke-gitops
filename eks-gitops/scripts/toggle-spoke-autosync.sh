#!/usr/bin/env bash
# 스포크 애드온 appset 의 ArgoCD auto-sync(automated 블록) 토글.
#   disable : automated 블록을 주석 처리 → 생성되는 Application 전부 수동 sync (selfHeal 정지)
#   enable  : 주석 해제 → 원상 복구 (각 파일 원래 prune 설정 보존)
#   status  : 현재 상태 표시
#
# 용도: blue/green 업그레이드 중 blue 동결 / 평시 수동운영. 주석 방식이라 파일별 원본 그대로 복원.
# 대상: platform/spoke/_appsets/*-appset.yaml  (project-spoke.yaml=AppProject 제외)
# ⚠️ 파일만 바꾼다. 반영은 git push + 상위 앱(app-of-apps-svc/appset-of-appsets) 수동 sync.
set -euo pipefail

MODE="${1:-status}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/platform/spoke/_appsets"
SENT="#autosync# "   # 우리가 붙인 주석만 골라내는 표식

python3 - "$MODE" "$DIR" "$SENT" <<'PY'
import sys, os, re, glob

mode, dirp, SENT = sys.argv[1], sys.argv[2], sys.argv[3]
files = sorted(f for f in glob.glob(os.path.join(dirp, "*-appset.yaml"))
               if not f.endswith("project-spoke.yaml"))

def disable(lines):
    out, i, n = [], 0, len(lines)
    while i < n:
        m = re.match(r'^(\s*)automated:\s*$', lines[i])
        if m:
            ind = len(m.group(1)); block = [i]; j = i+1
            while j < n and lines[j].strip() and (len(lines[j]) - len(lines[j].lstrip(" "))) > ind:
                block.append(j); j += 1
            for k in block:
                s = lines[k]; pad = s[:len(s)-len(s.lstrip(" "))]
                out.append(f"{pad}{SENT}{s[len(pad):]}")   # 줄 끝(개행 유무) 원본 보존
            i = block[-1] + 1; continue
        out.append(lines[i]); i += 1
    # automated 만 있던 syncPolicy: 는 빈 매핑 방지로 함께 주석
    res = []
    for idx, s in enumerate(out):
        m = re.match(r'^(\s*)syncPolicy:\s*$', s)
        if m:
            ind = len(m.group(1)); has_real = False
            for t in out[idx+1:]:
                if not t.strip(): continue
                tind = len(t) - len(t.lstrip(" "))
                if tind <= ind: break
                if SENT not in t: has_real = True; break
            if not has_real:
                pad = s[:len(s)-len(s.lstrip(" "))]
                res.append(f"{pad}{SENT}{s[len(pad):]}"); continue
        res.append(s)
    return res

def enable(lines):
    pat = re.compile(r'^(\s*)' + re.escape(SENT))
    return [pat.sub(r'\1', s) for s in lines]

def count_auto(lines):   # 활성(주석 안 된) automated 개수
    return sum(1 for s in lines if re.match(r'^\s*automated:\s*$', s))

changed = 0
for f in files:
    lines = open(f).readlines()
    if mode == "status":
        state = "AUTO" if count_auto(lines) else ("manual" if any(SENT in s for s in lines) else "manual(none)")
        print(f"  {'AUTO ⚠️ ' if state=='AUTO' else 'manual ✓'}  {os.path.basename(f)}")
        continue
    new = disable(lines) if mode == "disable" else enable(lines) if mode == "enable" else None
    if new is None:
        sys.exit(f"usage: toggle-spoke-autosync.sh [disable|enable|status]")
    if new != lines:
        open(f, "w").writelines(new); changed += 1

if mode != "status":
    print(f"[{mode}] {changed}개 파일 변경 ({len(files)}개 중). git diff 로 검토 후 push.")
PY