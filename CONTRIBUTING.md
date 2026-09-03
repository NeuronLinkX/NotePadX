# NotepadX 기여 가이드

각 기능의 동작 원리나 세부 스펙은 다루지 않고, **위치**와 **레이어 사이의 흐름**만 안내합니다.

## 1. 레이어 구조

```
App          진입점, DI(의존성 조립), 메뉴/커맨드
Features     SwiftUI View + ViewModel (기능 단위 폴더)
Domain       UseCase(비즈니스 로직) + Repository 프로토콜 + Model
Data         Domain의 Repository 프로토콜을 SQLite로 구현
Services     여러 기능이 공유하는 것 (자동저장 조율, Keychain 등)
WebEditor    Swift가 아닌 별도 npm 서브프로젝트 (Tiptap 리치 에디터)
```

의존 방향은 항상 `Features → Domain ← Data` 입니다. Feature의 ViewModel은 UseCase만 알고, UseCase는 Repository *프로토콜*만 알 뿐 SQLite를 직접 모릅니다. 새 저장소 구현체를 추가하고 싶으면(Data 레이어를 안 건드리고) `Domain/Repositories/*.swift`의 프로토콜만 보고 새 구현체를 만들면 됩니다.

## 2. 기능별 위치

| 기능 | 위치 |
|---|---|
| 앱 진입점 / 메뉴·단축키 / 의존성 조립 | [App/NotepadXApp.swift](Sources/NotepadX/App/NotepadXApp.swift), [App/AppDelegate.swift](Sources/NotepadX/App/AppDelegate.swift), [App/AppCommands.swift](Sources/NotepadX/App/AppCommands.swift), [App/AppEnvironment.swift](Sources/NotepadX/App/AppEnvironment.swift) |
| 3열 레이아웃(사이드바/목록/편집기) 뼈대 | [App/RootView.swift](Sources/NotepadX/App/RootView.swift), [App/ContentView.swift](Sources/NotepadX/App/ContentView.swift) |
| 노트/폴더/태그 등 도메인 모델 | [Domain/Models/](Sources/NotepadX/Domain/Models/) (`Note`, `Folder`, `Tag`, `EditorDocument`, `NoteRevision`, `SearchHit`, `SyncDocument` 등) |
| 노트 CRUD, 휴지통, 낙관적 동시성(`saveIfUnchanged`) | [Domain/UseCases/NoteUseCase.swift](Sources/NotepadX/Domain/UseCases/NoteUseCase.swift) |
| 자동저장 디바운스 / 앱 비활성화·종료 시 강제 flush | [Services/AutosaveService.swift](Sources/NotepadX/Services/AutosaveService.swift), [Services/SaveCoordinator.swift](Sources/NotepadX/Services/SaveCoordinator.swift) |
| 폴더 계층 | [Domain/UseCases/FolderUseCase.swift](Sources/NotepadX/Domain/UseCases/FolderUseCase.swift), [Data/Repositories/SQLiteFolderRepository.swift](Sources/NotepadX/Data/Repositories/SQLiteFolderRepository.swift) |
| 태그 부여 / 삭제 시 미사용 태그 자동 정리 | [Domain/UseCases/TagUseCase.swift](Sources/NotepadX/Domain/UseCases/TagUseCase.swift), [Features/NoteList/NoteListViewModel.swift](Sources/NotepadX/Features/NoteList/NoteListViewModel.swift)의 `deleteNotesPermanentlyAndPruneOrphanedTags` |
| 전문 검색 (FTS5, 한글 부분 문자열) | [Domain/UseCases/SearchUseCase.swift](Sources/NotepadX/Domain/UseCases/SearchUseCase.swift), [Data/Search/SearchIndexService.swift](Sources/NotepadX/Data/Search/SearchIndexService.swift), 검색 결과 하이라이트는 [Features/NoteList/SearchSnippetBuilder.swift](Sources/NotepadX/Features/NoteList/SearchSnippetBuilder.swift) |
| 버전 기록(자동/수동 스냅샷) · diff 뷰 · 복원 | [Domain/UseCases/NoteRevisionUseCase.swift](Sources/NotepadX/Domain/UseCases/NoteRevisionUseCase.swift), [Data/Repositories/SQLiteNoteRevisionRepository.swift](Sources/NotepadX/Data/Repositories/SQLiteNoteRevisionRepository.swift), [Features/Editor/RevisionHistoryView.swift](Sources/NotepadX/Features/Editor/RevisionHistoryView.swift) |
| SQLite 스키마 정의 / 마이그레이션 | [Data/Database/DatabaseManager.swift](Sources/NotepadX/Data/Database/DatabaseManager.swift), [Data/Database/SchemaMigrator.swift](Sources/NotepadX/Data/Database/SchemaMigrator.swift) |
| 노트 목록 / 체크박스 다중 선택·삭제 | [Features/NoteList/NoteListView.swift](Sources/NotepadX/Features/NoteList/NoteListView.swift), [Features/NoteList/NoteListViewModel.swift](Sources/NotepadX/Features/NoteList/NoteListViewModel.swift) |
| 사이드바 (폴더/태그 트리, 즐겨찾기, 최근) | [Features/Sidebar/](Sources/NotepadX/Features/Sidebar/) |
| 리치 에디터 — Swift 쪽 껍데기(WKWebView 래핑, 툴바) | [Features/Editor/EditorView.swift](Sources/NotepadX/Features/Editor/EditorView.swift), [Features/Editor/EditorViewModel.swift](Sources/NotepadX/Features/Editor/EditorViewModel.swift), [Features/Editor/RichEditor/](Sources/NotepadX/Features/Editor/RichEditor/) |
| 리치 에디터 — Swift↔JS 브리지 프로토콜 | [Features/Editor/RichEditor/EditorBridge.swift](Sources/NotepadX/Features/Editor/RichEditor/EditorBridge.swift), [EditorBridgeMessages.swift](Sources/NotepadX/Features/Editor/RichEditor/EditorBridgeMessages.swift) — 자세한 규약은 3절 참고 |
| 리치 에디터 — 실제 편집기 본체(Tiptap, JS) | [WebEditor/src/editor.js](WebEditor/src/editor.js)(확장 등록·툴바 커맨드·브리지), [WebEditor/src/extensions.js](WebEditor/src/extensions.js)(커스텀 노드: 이미지 리사이즈, 화살표 자동변환, 접이식 블록 등), [WebEditor/src/sanitize.js](WebEditor/src/sanitize.js)(붙여넣기 HTML 정제), [WebEditor/src/markdownPaste.js](WebEditor/src/markdownPaste.js)(text/html 없는 순수 텍스트 붙여넣기를 마크다운으로 인식해 렌더링), [WebEditor/src/languages.js](WebEditor/src/languages.js)(코드 하이라이트 언어) |
| 메모 목록 → 사이드바 폴더 드래그 앤 드롭 | [Domain/Models/NoteDragPayload.swift](Sources/NotepadX/Domain/Models/NoteDragPayload.swift)(`NSItemProvider` 인코딩/디코딩, `com.notepadx.app.note-id-list`는 [Resources/Info.plist](Sources/NotepadX/Resources/Info.plist)의 `UTExportedTypeDeclarations`에도 선언되어 있다), [Features/NoteList/NoteListView.swift](Sources/NotepadX/Features/NoteList/NoteListView.swift)(`.onDrag`), [Features/Sidebar/SidebarView.swift](Sources/NotepadX/Features/Sidebar/SidebarView.swift)(`.onDrop`), `NoteListViewModel.moveNotes` |
| 분할 편집(좌우/상하) | [Features/Editor/Split/](Sources/NotepadX/Features/Editor/Split/) |
| 문서 개요(왼쪽 제목 목차) / 상태 표시줄 글자수·단어수 | [Features/Editor/DocumentOutlineView.swift](Sources/NotepadX/Features/Editor/DocumentOutlineView.swift), `EditorViewModel.headingOutline`/`scrollToHeading`/`documentWordCount`, JS 쪽 `postHeadings`/`scrollToHeading` 커맨드([WebEditor/src/editor.js](WebEditor/src/editor.js)) |
| 파일 첨부(이미지 아닌 파일 드래그·붙여넣기) | [Services/AttachmentStorage.swift](Sources/NotepadX/Services/AttachmentStorage.swift)(디스크 저장), `EditorViewModel`의 `didRequestSaveAttachment`/`didRequestOpenAttachment`, JS 쪽 `insertFileAttachments`/`FileAttachment` 노드뷰(파일 종류별 아이콘)([WebEditor/src/editor.js](WebEditor/src/editor.js), [WebEditor/src/extensions.js](WebEditor/src/extensions.js)) |
| 내보내기 (TXT/MD/HTML/RTF/PDF/DOCX) | [Features/Export/](Sources/NotepadX/Features/Export/), 포맷별 실제 구현은 [Features/Export/Exporters/](Sources/NotepadX/Features/Export/Exporters/) |
| OneDrive 동기화 (Microsoft Graph OAuth, 3-way 충돌) | [Features/OneDrive/](Sources/NotepadX/Features/OneDrive/), [Domain/UseCases/OneDriveSyncUseCase.swift](Sources/NotepadX/Domain/UseCases/OneDriveSyncUseCase.swift) |
| AI 글쓰기 보조 (OpenAI 연동, 스트리밍) | [Features/LLM/](Sources/NotepadX/Features/LLM/) — `OpenAIClient.swift`(HTTP/스트리밍), `PromptBuilder.swift`(작업별 프롬프트), `LLMPanelView(Model).swift`(패널 UI) |
| API 키 등 민감정보 저장 | [Services/KeychainService.swift](Sources/NotepadX/Services/KeychainService.swift) |
| 앱 리소스(아이콘, Info.plist, entitlements) | [Sources/NotepadX/Resources/](Sources/NotepadX/Resources/) |

## 3. Swift ↔ JS 브리지 규약

리치 에디터는 WKWebView 안에서 Tiptap이 돌아가고, `WKScriptMessageHandler`로 Swift와 통신합니다. 이름 없이 아무 메시지나 주고받지 않고, 양쪽 다 **화이트리스트 방식**입니다.

- **JS → Swift**: [EditorBridgeMessages.swift](Sources/NotepadX/Features/Editor/RichEditor/EditorBridgeMessages.swift)의 `IncomingBridgeMessageType` (`ready`/`docChanged`/`headingsChanged`/`selectionChanged`/`openExternalLink`/`saveAttachment`/`openAttachment`/`error`)에 없는 메시지는 무시하지 않고 에러로 되돌아갑니다.
- **Swift → JS**: [EditorBridge.swift](Sources/NotepadX/Features/Editor/RichEditor/EditorBridge.swift)가 `evaluateJavaScript`로 `window.NotepadXBridge`(정의는 [editor.js](WebEditor/src/editor.js) 맨 아래)의 메서드를 직접 호출합니다.
- 문서는 `EditorDocument`/`EditorNode` (Codable, [EditorDocument.swift](Sources/NotepadX/Domain/Models/EditorDocument.swift))로 왕복합니다. `attrs: [String: JSONValue]?`가 임의의 JSON 속성을 그대로 보존하므로, Tiptap 쪽에 새 노드 속성(예: 이미지 `width`)을 추가해도 **Swift 쪽 모델을 안 고쳐도 됩니다**.

## 4. WebEditor(JS)를 고쳤다면 반드시

`WebEditor/src/*.js`를 고치는 것만으로는 앱에 반영되지 않습니다. 앱은 미리 번들된 [Sources/NotepadX/Resources/WebEditor/dist/editor.bundle.js](Sources/NotepadX/Resources/WebEditor/dist/editor.bundle.js)를 로드합니다.

```bash
cd WebEditor
npm install   # 최초 1회
npm run build # dist/editor.bundle.js를 다시 생성 (esbuild)
```

빌드된 `dist/editor.bundle.js`는 **저장소에 커밋되는 산출물**입니다 — 소스만 고치고 빌드를 깜빡하면 리뷰에서 "소스는 바뀌었는데 번들은 그대로"인 diff가 나옵니다. [Tests/NotepadXTests/WebEditorResourcesTests.swift](Tests/NotepadXTests/WebEditorResourcesTests.swift)가 번들이 비어있지 않은지 정도만 최소한으로 잡아줍니다.

## 5. 빌드 & 테스트

```bash
swift build && swift test        # 커맨드라인, GUI 없이 로직만
xcodegen generate                # NotepadX.xcodeproj 생성 (커밋 안 함)
open NotepadX.xcodeproj          # Xcode에서 실제 앱 실행/디버깅
```

에디터 관련 테스트([Tests/NotepadXTests/WebEditorNewFeatureTests.swift](Tests/NotepadXTests/WebEditorNewFeatureTests.swift))는 진짜 `WKWebView`를 띄우고 `NSEvent` keyDown, `ClipboardEvent`/`DragEvent`/`PointerEvent`를 실제로 dispatch해서 검증합니다. `document.execCommand`나 DOM 직접 조작으로는 Tiptap의 InputRule/paste 파이프라인을 안 타는 경우가 있어서, 되도록 이 패턴(실제 이벤트 시뮬레이션 + `docChanged`로 넘어온 문서 검증)을 따라주세요.

## 6. PR 내기 전 체크리스트

- [ ] `WebEditor/src/*`를 고쳤으면 `npm run build`로 `dist/editor.bundle.js`도 같이 갱신됐는지
- [ ] `swift test` 전체 통과
- [ ] UI를 건드렸으면 `xcodebuild`로 실제 빌드해서 앱을 띄워 직접 확인
- [ ] README.md의 기능 설명과 실제 동작이 어긋나지 않는지
