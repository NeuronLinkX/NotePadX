# NotepadX

macOS용 노트 앱. 리치 텍스트/코드 편집, 폴더·태그 정리, 분할 편집, OneDrive 동기화, 다양한 형식 내보내기, OpenAI 기반 AI 글쓰기 보조를 지원한다.

## 주요 기능

- **리치 텍스트 편집**: 굵게·기울임·밑줄·취소선·글자색·형광펜·글자크기, 제목(1~6), 글머리표·번호·체크리스트, 인용문, 표, 이미지, 링크, 수평선, 접을 수 있는 세부 블록
- **코드 블록**: 18개 언어 구문 강조
- **폴더·태그**: 계층형 폴더, 다중 태그, 즐겨찾기, 휴지통(30일 후 자동 삭제)
- **전문 검색**: 제목·본문·코드·태그·폴더를 한 번에 검색 (한글 부분 문자열 검색 지원)
- **버전 기록**: 자동/수동 스냅샷, 줄 단위 비교, 복원
- **분할 편집**: 좌우/상하 분할, 같은 문서 동시 편집 시 저장 충돌 방지, 패널별 편집/미리보기 전환
- **OneDrive 동기화**: 폴더를 한 번 고르면 그 뒤로는 노트를 저장할 때마다 자동으로 동기화된다("지금 동기화"를 매번 누를 필요 없음). 선택 시 Microsoft Graph OAuth 연동, 3-way 충돌 감지로 자동 덮어쓰기 없이 로컬/원격/둘 다 보존 중 선택
- **내보내기**: Plain Text, Markdown, HTML, RTF, RTFD, PDF, DOCX(Word 서식·자동 번호 매기기 포함), 앱 전용 JSON
- **AI 글쓰기 보조**: OpenAI 연동 — 요약, 문장 다듬기, 맞춤법 교정, 번역, 제목/목차 생성, 코드 설명·리팩터링 등 21종 작업, 스트리밍 응답

## 요구 사항

- macOS 14 이상
- Xcode 15 이상
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## 빌드 및 실행

```bash
xcodegen generate
open NotepadX.xcodeproj
```

Xcode에서 `NotepadX` 스킴을 선택하고 Cmd-R로 실행한다. 최초 실행 시 Signing & Capabilities에서 서명 팀을 본인 Apple ID로 지정해야 한다.

커맨드라인으로 빌드/테스트만 하려면:

```bash
swift build
swift test
```

## AI 기능 사용 설정

AI 패널은 `OPENAI_API_KEY` 환경 변수로만 키를 읽는다. 앱 안에서 입력·저장하는 기능은 없다.

```bash
export OPENAI_API_KEY="sk-..."
```

Finder/Dock에서 더블클릭으로 실행하는 `.app`은 `~/.zshrc` 같은 셸 설정을 읽지 않는다. GUI로 실행하는 앱에도 적용하려면:

```bash
launchctl setenv OPENAI_API_KEY "sk-..."
```

등록한 뒤에는 앱을 (다시 실행 중이었다면 종료 후) 새로 시작해야 반영된다. 단, `launchctl setenv`는 **로그아웃/재부팅하면 초기화**된다.

### 재부팅해도 유지되게 (LaunchAgent)

로그인할 때마다 자동으로 `launchctl setenv`를 실행해주는 LaunchAgent를 등록하면 재부팅 후에도 계속 적용된다.

```bash
mkdir -p ~/Library/LaunchAgents
cat <<'EOF' > ~/Library/LaunchAgents/com.notepadx.env.openai-api-key.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.notepadx.env.openai-api-key</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/launchctl</string>
        <string>setenv</string>
        <string>OPENAI_API_KEY</string>
        <string>여기에_실제_키_붙여넣기</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
```

```bash
# 1) 실제 키로 교체
open -e ~/Library/LaunchAgents/com.notepadx.env.openai-api-key.plist
# "여기에_실제_키_붙여넣기" 부분을 sk-proj-... 로 바꾸고 저장

# 2) 지금 바로 적용 (재부팅 안 해도 즉시 반영)
launchctl load ~/Library/LaunchAgents/com.notepadx.env.openai-api-key.plist

# 3) NotepadX 재시작
killall NotepadX 2>/dev/null
open build/NotepadX.app
```

이 plist 파일도 평문 텍스트라 `~/.zshrc`에 적는 것과 보안 수준은 동일하다(계정 소유자만 읽을 수 있는 홈 디렉터리 안이라는 점에서). 더 안전하게 Keychain으로 관리하고 싶다면 앱 안에 API 키 저장 기능을 다시 넣어야 한다(현재는 의도적으로 제거된 상태).

## 데이터 저장 위치

- 데이터베이스: `~/Library/Application Support/NotepadX/NotepadX.sqlite`
- 첨부파일: `~/Library/Application Support/NotepadX/Attachments/`# NotePadX
