#!/usr/bin/env bash
# 이미 Developer ID Application으로 서명된 DMG를 Apple에 공증 제출하고 staple까지 한다.
#
# 사전 준비(유료 Apple Developer Program 계정이 필요하다 — 이 저장소만으로는 할 수 없다):
#   1) project.yml의 DEVELOPMENT_TEAM에 팀 ID를 넣고, 서명 ID를 "Developer ID Application"으로 바꾼 뒤
#      Scripts/build_dmg.sh Release 로 서명된 .app/.dmg를 만든다. 앱과 위젯 모두 Hardened Runtime으로 서명돼야 한다.
#   2) 공증 자격 증명을 키체인에 한 번 저장한다(앱 전용 암호 사용):
#        xcrun notarytool store-credentials NOTEPADX_NOTARY --apple-id <애플 ID> --team-id <팀 ID>
#
# 사용법: NOTARY_PROFILE=NOTEPADX_NOTARY Scripts/notarize.sh build/Notepad-<버전>.dmg
#
# 주의: 이 스크립트는 작성자 환경에 Apple 계정이 없어 실제로 실행해 보지 못했다. 첫 실행 때 출력을 확인할 것.
set -euo pipefail

DMG="${1:?사용법: NOTARY_PROFILE=<키체인 프로필> $0 <dmg 경로>}"
PROFILE="${NOTARY_PROFILE:?NOTARY_PROFILE(notarytool 키체인 프로필 이름)을 지정하세요}"

[ -f "$DMG" ] || { echo "DMG가 없습니다: $DMG" >&2; exit 2; }

echo "==> 공증 제출 (보통 몇 분 걸립니다)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> staple"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Gatekeeper 확인"
spctl -a -t open --context context:primary-signature -vv "$DMG"
echo "완료: $DMG"
