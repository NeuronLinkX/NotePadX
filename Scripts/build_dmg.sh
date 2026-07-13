#!/usr/bin/env bash
set -euo pipefail

# NotepadX를 배포용 DMG로 패키징한다.
#
# 사용법: Scripts/build_dmg.sh [Release|Debug]  (기본값 Release)
#
# 이 스크립트가 하는 일:
#   1) xcodegen으로 .xcodeproj 재생성
#   2) xcodebuild archive로 .app 빌드/서명
#   3) .app + /Applications 심볼릭 링크를 담은 DMG 생성
#
# 배포 전 반드시 알아야 할 것 (README "11. Notarization(공증) 절차" 참고):
#   - project.yml의 DEVELOPMENT_TEAM이 비어 있으면(기본값) ad-hoc 서명만 되고,
#     이 DMG를 내려받은 다른 사람의 Mac에서는 Gatekeeper가 "확인되지 않은 개발자"
#     경고를 띄우거나 아예 실행을 막는다.
#   - GitHub Releases에 경고 없이 올리려면: 유료 Apple Developer Program 계정으로
#     발급한 Developer ID Application 인증서로 서명 → `xcrun notarytool submit --wait`
#     → `xcrun stapler staple`까지 마친 뒤 이 스크립트를 다시 돌리거나, 이 스크립트가
#     만든 .app에 staple만 따로 실행한다.
#   - App Store 배포는 DMG를 쓰지 않는다. 별도로 App Store distribution 인증서/
#     프로비저닝 프로필로 다시 archive해서 Xcode Organizer(또는 Transporter 앱)로
#     업로드해야 한다 — 이 스크립트의 범위 밖이다.

APP_NAME="NotepadX"
CONFIGURATION="${1:-Release}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_STAGING="$BUILD_DIR/dmg-staging"
VERSION="$(defaults read "$ROOT_DIR/Sources/NotepadX/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.1.0")"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> xcodegen generate"
cd "$ROOT_DIR"
xcodegen generate

echo "==> xcodebuild archive ($CONFIGURATION)"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration "$CONFIGURATION" \
  archive -archivePath "$ARCHIVE_PATH"

echo "==> Extracting .app from archive"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"

echo "==> Staging DMG contents"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

echo "==> Creating DMG"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

echo ""
echo "==> 서명/공증 상태 점검"
codesign -dv "$APP_PATH" 2>&1 | grep -E "flags|Authority" || true
if spctl -a -vvv "$APP_PATH" 2>&1; then
  echo "  Gatekeeper: accepted (공증 완료된 것으로 보임)"
else
  echo "  Gatekeeper: rejected — Developer ID 서명 + notarize + staple 전이면 정상. 배포 전 README 11절을 따르세요."
fi

echo ""
echo "완료: $DMG_PATH"
