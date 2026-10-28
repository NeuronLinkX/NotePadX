#!/usr/bin/env bash
# NotepadX UI 스모크 테스트 — 앱을 실제로 띄워서 "탭이 복원되고, 탭을 누르면 해당 메모가 열리는지"를
# 접근성(AX) API로 확인한다. 탭 클릭이 패키징된 앱에서만 먹통이던 문제처럼 유닛 테스트로는 못 잡는
# 회귀를 잡기 위한 것이다.
#
# - 격리 프로필(NOTEPADX_PROFILE=smoke)에 가짜 메모를 채워서 쓴다. 실제 메모·설정·Keychain은 건드리지 않는다.
# - 사전 조건: 이 스크립트를 실행하는 터미널 앱에 시스템 설정 > 개인정보 보호 > '손쉬운 사용' 권한.
# - 한계: AX '누르기' 동작으로 탭을 누르므로, 마우스 이벤트가 뷰까지 도달하는지(히트 테스트)까지는
#   검증하지 못한다. 그 부분은 사람이 한 번 눌러 보는 것으로 남는다.
#
# 사용법: Scripts/ui_smoke.sh            (debug 빌드로 실행)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
PROFILE="smoke"
SUPPORT="$HOME/Library/Application Support/NotepadX-$PROFILE"
DEFAULTS_DOMAIN="com.notepadx.app.$PROFILE"
APP_LOG="$(mktemp -t notepadx_smoke_app)"
FAILURES=0

T_WEEKLY="주간 회의록 — 10월 4주차"
T_BOOK="독서 메모: 클린 아키텍처"
T_JEJU="제주 여행 계획"

cleanup() {
  pkill -f ".build/debug/NotepadX" 2>/dev/null || true
  sleep 1
  rm -rf "$SUPPORT"
  defaults delete "$DEFAULTS_DOMAIN" 2>/dev/null || true
  rm -f "$APP_LOG"
}
trap cleanup EXIT

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; FAILURES=$((FAILURES + 1)); }

ax() { osascript -e "$1" 2>/dev/null || true; }

# 편집기 제목 필드(AXTextField)의 현재 값
current_title() {
  ax 'tell application "System Events" to tell process "NotepadX"
    set els to entire contents of window 1
    repeat with i from 1 to count of els
      try
        if role of (item i of els) is "AXTextField" then return (value of (item i of els)) as text
      end try
    end repeat
    return ""
  end tell'
}

editor_text() {
  ax 'tell application "System Events" to tell process "NotepadX"
    set els to entire contents of window 1
    repeat with i from 1 to count of els
      try
        if role of (item i of els) is "AXTextArea" then return (value of (item i of els)) as text
      end try
    end repeat
    return ""
  end tell'
}

tab_count() {
  ax 'tell application "System Events" to tell process "NotepadX"
    set n to 0
    set els to entire contents of window 1
    repeat with i from 1 to count of els
      try
        if role of (item i of els) is "AXButton" and (description of (item i of els)) starts with "탭:" then set n to n + 1
      end try
    end repeat
    return n
  end tell'
}

press_tab() {
  ax "tell application \"System Events\" to tell process \"NotepadX\"
    set els to entire contents of window 1
    repeat with i from 1 to count of els
      try
        if role of (item i of els) is \"AXButton\" and (description of (item i of els)) is \"탭: $1\" then
          click (item i of els)
          return \"pressed\"
        end if
      end try
    end repeat
    return \"not found\"
  end tell"
}

# 값이 기대와 같아질 때까지 최대 8초 기다린다.
expect_title() {
  local expected="$1" label="$2" got=""
  for _ in $(seq 1 16); do
    got="$(current_title)"
    if [ "$got" = "$expected" ]; then pass "$label → 제목 '$expected'"; return; fi
    sleep 0.5
  done
  fail "$label → 제목이 '$expected'이어야 하는데 '$got'"
}

echo "== 1. 빌드와 가짜 데이터 준비"
swift build >/dev/null
NOTEPADX_PROFILE="$PROFILE" NOTEPADX_SEED_DEMO=1 swift test --filter DemoDataSeeder >/dev/null 2>&1 \
  || { echo "시드 실패"; exit 2; }
DB="$SUPPORT/NotepadX.sqlite"
ID_WEEKLY="$(sqlite3 "$DB" "select id from note where title like '주간 회의록%';")"
ID_BOOK="$(sqlite3 "$DB" "select id from note where title like '독서 메모%';")"
ID_JEJU="$(sqlite3 "$DB" "select id from note where title like '제주%';")"
# 지난번 세션이 남겨 둔 탭 상태를 흉내 낸다 — 실제 복원 경로를 태우기 위해서다.
defaults write "$DEFAULTS_DOMAIN" NotepadX.tabs.open -array "$ID_WEEKLY" "$ID_BOOK" "$ID_JEJU"
defaults write "$DEFAULTS_DOMAIN" NotepadX.tabs.active "$ID_BOOK"
pass "가짜 메모 8개와 저장된 탭 3개 준비"

echo "== 2. 앱 실행"
(NOTEPADX_PROFILE="$PROFILE" NOTEPADX_SKIP_MAINTENANCE=1 nohup .build/debug/NotepadX >"$APP_LOG" 2>&1 &)
for _ in $(seq 1 40); do
  [ "$(ax 'tell application "System Events" to tell process "NotepadX" to count windows')" = "1" ] && break
  sleep 0.5
done
osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "NotepadX") to true' >/dev/null 2>&1 || true
sleep 3

echo "== 3. 탭 복원"
for _ in $(seq 1 16); do [ "$(tab_count)" = "3" ] && break; sleep 0.5; done
[ "$(tab_count)" = "3" ] && pass "저장해 둔 탭 3개가 복원됨" || fail "탭이 3개여야 하는데 $(tab_count)개"
expect_title "$T_BOOK" "마지막에 보던 메모가 다시 선택됨"
case "$(editor_text)" in *"의존성은 항상 안쪽"*) pass "편집기 본문이 실제로 로드됨" ;; *) fail "편집기 본문이 비어 있음" ;; esac

echo "== 4. 탭을 누르면 해당 메모가 열리는지"
[ "$(press_tab "$T_WEEKLY")" = "pressed" ] && expect_title "$T_WEEKLY" "첫 번째 탭" || fail "첫 번째 탭 버튼을 찾지 못함"
[ "$(press_tab "$T_JEJU")" = "pressed" ] && expect_title "$T_JEJU" "세 번째 탭" || fail "세 번째 탭 버튼을 찾지 못함"
[ "$(press_tab "$T_BOOK")" = "pressed" ] && expect_title "$T_BOOK" "두 번째 탭" || fail "두 번째 탭 버튼을 찾지 못함"

echo
if [ "$FAILURES" -eq 0 ]; then echo "스모크 테스트 통과"; else echo "스모크 테스트 실패: $FAILURES건"; exit 1; fi
