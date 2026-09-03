import AppKit
import Foundation

/// 오른쪽 접을 수 있는 AI 패널의 상태. 현재 편집 중인 문서(EditorViewModel)와 연결되지만,
/// 응답 기록은 노트 본문과 별도로 이 뷰모델 안에서만 관리한다 (스펙 17절).
@MainActor
final class LLMPanelViewModel: ObservableObject {
    @Published var isVisible = false
    @Published var task: AITaskType = .summarize
    @Published var customPrompt = ""
    @Published var scope: AIContextScope = .selectionOnly
    @Published private(set) var responseText = ""
    @Published private(set) var isStreaming = false
    @Published var errorMessage: String?
    @Published var lastAppliedAction: AIApplyAction?
    @Published var isShowingMissingKeyWarning = false
    @Published var isShowingBillingAlert = false

    private let llmUseCase: LLMUseCase
    private let editorViewModel: EditorViewModel
    private var streamTask: Task<Void, Never>?

    init(editorViewModel: EditorViewModel, llmUseCase: LLMUseCase = LLMUseCase()) {
        self.editorViewModel = editorViewModel
        self.llmUseCase = llmUseCase
    }

    var hasAPIKey: Bool { llmUseCase.hasAPIKey() }

    /// 전송 전에 "무엇을 얼마나 보내는지" 보여주기 위한 값들 (스펙 16절).
    var pendingContent: String { contentForScope() }
    var estimatedCharacterCount: Int {
        LLMUseCase.estimatedCharacterCount(content: pendingContent, task: task, customPrompt: customPrompt)
    }

    /// 패널을 열 때마다 호출한다 — 키가 전혀 없으면(Keychain도, `OPENAI_API_KEY` 환경 변수도 없음)
    /// 인라인 안내문만으로는 놓치기 쉬워서 명시적인 경고창을 한 번 띄운다.
    func checkAPIKeyAvailability() {
        isShowingMissingKeyWarning = !hasAPIKey
    }

    func changeTask(_ newTask: AITaskType) {
        task = newTask
        scope = newTask.defaultScope
    }

    private func contentForScope() -> String {
        switch scope {
        case .selectionOnly, .codeBlockOnly:
            return editorViewModel.selection.selectedText
        case .fullDocument:
            return editorViewModel.exportDocument?.derivedPlainText ?? ""
        }
    }

    /// 사용자가 "전송" 버튼을 눌렀을 때만 호출된다 — 그 전에는 아무것도 서버로 나가지 않는다.
    func send() {
        errorMessage = nil
        responseText = ""
        lastAppliedAction = nil
        let content = pendingContent

        guard task == .custom || !content.isEmpty else {
            errorMessage = "보낼 내용이 없습니다. 텍스트를 선택하거나 범위를 바꿔보세요."
            return
        }
        if task == .custom, customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "사용자 정의 프롬프트를 입력하세요."
            return
        }

        do {
            let stream = try llmUseCase.streamResponse(
                task: task,
                customPrompt: customPrompt,
                content: content,
                documentTitle: editorViewModel.title,
                codeLanguage: scope == .codeBlockOnly ? editorViewModel.selection.codeBlockLanguage : nil
            )
            isStreaming = true
            streamTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await fragment in stream {
                        self.responseText += fragment
                    }
                } catch is CancellationError {
                    // 사용자가 중지를 누른 경우 — 오류로 표시하지 않는다.
                } catch {
                    self.report(error)
                }
                self.isStreaming = false
            }
        } catch {
            report(error)
        }
    }

    /// 크레딧 소진(billing) 오류는 "잠시 후 재시도"로 해결되지 않으므로, 인라인 빨간 텍스트
    /// 말고 놓치기 어려운 경고창으로 따로 띄운다.
    private func report(_ error: Error) {
        if case AIClientError.billingRequired = error {
            isShowingBillingAlert = true
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func openBillingPage() {
        NSWorkspace.shared.open(URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func retry() {
        send()
    }

    func clearResponse() {
        responseText = ""
        errorMessage = nil
        lastAppliedAction = nil
    }

    // MARK: - 적용 (스펙 17절)

    func apply(_ action: AIApplyAction) async {
        guard !responseText.isEmpty else { return }
        if action.requiresRevisionBeforeApply {
            await editorViewModel.snapshotBeforeLLMReplace()
        }
        switch action {
        case .replaceSelection:
            editorViewModel.perform(command: "replaceSelectionWithText", args: ["text": responseText])
        case .insertBelowSelection:
            editorViewModel.perform(command: "insertTextBelowSelection", args: ["text": responseText])
        case .insertAtEnd:
            editorViewModel.perform(command: "insertTextAtEnd", args: ["text": responseText])
        case .newNote:
            await editorViewModel.createNoteFromText(title: "\(task.displayName) 결과", text: responseText)
        case .panelOnly:
            break
        }
        lastAppliedAction = action
    }

    func copyResponseToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(responseText, forType: .string)
    }
}
