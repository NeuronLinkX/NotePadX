import SwiftUI

/// 스펙 4/6/7/8절의 서식 도구 모음. 실제 서식 적용은 전부 JS 쪽 Tiptap 커맨드로 위임하고,
/// 이 뷰는 EditorViewModel.selection을 읽어 현재 활성 서식만 표시한다.
struct EditorToolbar: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var textColor = Color.primary
    @State private var highlightColor = Color.yellow
    @State private var isShowingLinkPrompt = false
    @State private var linkURLText = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                headingMenu

                Divider().frame(height: 16)

                markButton("bold", systemImage: "bold", label: "굵게")
                markButton("italic", systemImage: "italic", label: "기울임")
                markButton("underline", systemImage: "underline", label: "밑줄")
                markButton("strike", systemImage: "strikethrough", label: "취소선")
                markButton("code", systemImage: "chevron.left.forwardslash.chevron.right", label: "인라인 코드", command: "toggleInlineCode")

                Divider().frame(height: 16)

                ColorPicker("텍스트 색상", selection: $textColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 22)
                    .onChange(of: textColor) { _, newValue in
                        viewModel.perform(command: "setTextColor", args: ["color": newValue.hexString])
                    }
                ColorPicker("형광펜", selection: $highlightColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 22)
                    .onChange(of: highlightColor) { _, newValue in
                        viewModel.perform(command: "setHighlight", args: ["color": newValue.hexString])
                    }

                Divider().frame(height: 16)

                blockButton("bulletList", systemImage: "list.bullet", label: "글머리 기호 목록") { viewModel.perform(command: "toggleBulletList") }
                blockButton("orderedList", systemImage: "list.number", label: "번호 매기기 목록") { viewModel.perform(command: "toggleOrderedList") }
                blockButton("taskList", systemImage: "checklist", label: "체크리스트") { viewModel.perform(command: "toggleTaskList") }
                blockButton("blockquote", systemImage: "quote.opening", label: "인용문") { viewModel.perform(command: "toggleBlockquote") }

                Divider().frame(height: 16)

                codeBlockMenu

                Button { isShowingLinkPrompt = true } label: {
                    Image(systemName: "link")
                }
                .help("링크 추가")
                .accessibilityLabel("링크 추가")

                Button { viewModel.perform(command: "setHorizontalRule") } label: {
                    Image(systemName: "minus")
                }
                .help("구분선 삽입")
                .accessibilityLabel("구분선 삽입")

                Button { viewModel.perform(command: "insertDetails") } label: {
                    Image(systemName: "chevron.right.circle")
                }
                .help("접을 수 있는 세부 블록 삽입")
                .accessibilityLabel("접을 수 있는 세부 블록 삽입")

                Divider().frame(height: 16)

                tableMenu

                Spacer(minLength: 8)

                Button { viewModel.perform(command: "undo") } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("실행 취소")
                .accessibilityLabel("실행 취소")

                Button { viewModel.perform(command: "redo") } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .help("다시 실행")
                .accessibilityLabel("다시 실행")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .alert("링크 추가", isPresented: $isShowingLinkPrompt) {
            TextField("https://example.com", text: $linkURLText)
            Button("취소", role: .cancel) {}
            Button("추가") {
                if !linkURLText.isEmpty {
                    viewModel.perform(command: "setLink", args: ["href": linkURLText])
                }
                linkURLText = ""
            }
        }
    }

    private var headingMenu: some View {
        Menu {
            Button("본문") { viewModel.perform(command: "setParagraph") }
            ForEach(1...6, id: \.self) { level in
                Button("제목 \(level)") { viewModel.perform(command: "setHeading", args: ["level": level]) }
            }
        } label: {
            Label(headingLabel, systemImage: "textformat.size")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var codeBlockMenu: some View {
        Menu {
            ForEach(CodeLanguage.all) { language in
                Button(language.label) {
                    viewModel.perform(command: "toggleCodeBlock", args: ["language": language.value])
                }
            }
        } label: {
            Image(systemName: "curlybraces")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("코드 블록 삽입")
        .accessibilityLabel("코드 블록 삽입")
    }

    private var tableMenu: some View {
        Menu {
            Button("표 삽입 (3×3)") { viewModel.perform(command: "insertTable", args: ["rows": 3, "cols": 3]) }
            Divider()
            Button("위에 행 추가") { viewModel.perform(command: "addRowBefore") }
            Button("아래에 행 추가") { viewModel.perform(command: "addRowAfter") }
            Button("행 삭제") { viewModel.perform(command: "deleteRow") }
            Divider()
            Button("왼쪽에 열 추가") { viewModel.perform(command: "addColumnBefore") }
            Button("오른쪽에 열 추가") { viewModel.perform(command: "addColumnAfter") }
            Button("열 삭제") { viewModel.perform(command: "deleteColumn") }
            Divider()
            Button("셀 병합") { viewModel.perform(command: "mergeCells") }
            Button("셀 분할") { viewModel.perform(command: "splitCell") }
            Button("헤더 행 전환") { viewModel.perform(command: "toggleHeaderRow") }
            Divider()
            Button("표 삭제", role: .destructive) { viewModel.perform(command: "deleteTable") }
        } label: {
            Image(systemName: "tablecells")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("표 편집")
        .accessibilityLabel("표 편집")
    }

    private var headingLabel: String {
        if let level = viewModel.selection.headingLevel { return "제목 \(level)" }
        return "본문"
    }

    @ViewBuilder
    private func markButton(_ markName: String, systemImage: String, label: String, command: String? = nil) -> some View {
        let isActive = viewModel.selection.activeMarks.contains(markName)
        Button {
            viewModel.perform(command: command ?? "toggle\(markName.prefix(1).uppercased())\(markName.dropFirst())")
        } label: {
            Image(systemName: systemImage)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    @ViewBuilder
    private func blockButton(_ blockType: String, systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        let isActive = viewModel.selection.activeBlockType == blockType
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
