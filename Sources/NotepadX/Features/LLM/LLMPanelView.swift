import SwiftUI

/// 오른쪽에서 접고 펼치는 AI 패널 (스펙 17절).
struct LLMPanelView: View {
    @ObservedObject var viewModel: LLMPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !viewModel.hasAPIKey {
                missingAPIKeyNotice
            } else {
                taskPicker
                if viewModel.task == .custom {
                    customPromptField
                }
                scopePicker
                sendPreview
                actionButtons

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()
                responseArea
                if !viewModel.responseText.isEmpty {
                    applyButtons
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 300)
        .background(.regularMaterial)
        .onAppear { viewModel.checkAPIKeyAvailability() }
        .alert("OpenAI API 키가 없습니다", isPresented: $viewModel.isShowingMissingKeyWarning) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("AI 기능을 쓰려면 설정 > AI 탭에서 키를 한 번 등록하세요. 등록하면 계속 유지됩니다.")
        }
        .alert("결제(Billing) 충전이 필요합니다", isPresented: $viewModel.isShowingBillingAlert) {
            Button("Billing 페이지 열기") { viewModel.openBillingPage() }
            Button("확인", role: .cancel) {}
        } message: {
            Text("OpenAI 계정의 크레딧이 소진된 것 같습니다. 결제 정보를 확인하고 충전한 뒤 다시 시도하세요.")
        }
    }

    private var header: some View {
        HStack {
            Label("AI", systemImage: "sparkles")
                .font(.headline)
            Spacer()
            Button {
                viewModel.isVisible = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("AI 패널 닫기")
            .accessibilityLabel("AI 패널 닫기")
        }
    }

    private var missingAPIKeyNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenAI API 키가 설정되어 있지 않습니다.")
                .font(.callout)
            Text("설정 > AI 탭에서 키를 한 번 등록하면 계속 유지됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var taskPicker: some View {
        Picker("작업", selection: Binding(
            get: { viewModel.task },
            set: { viewModel.changeTask($0) }
        )) {
            ForEach(AITaskType.allCases) { task in
                Text(task.displayName).tag(task)
            }
        }
        .labelsHidden()
    }

    private var customPromptField: some View {
        TextEditor(text: $viewModel.customPrompt)
            .frame(height: 60)
            .overlay(alignment: .topLeading) {
                if viewModel.customPrompt.isEmpty {
                    Text("무엇을 해달라고 요청할까요?")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }

    private var scopePicker: some View {
        Picker("범위", selection: $viewModel.scope) {
            ForEach(AIContextScope.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var sendPreview: some View {
        HStack {
            Text("전송 예상 \(viewModel.estimatedCharacterCount)자")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isStreaming {
                Button("중지") { viewModel.stop() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("전송") { viewModel.send() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            if !viewModel.responseText.isEmpty, !viewModel.isStreaming {
                Button("재시도") { viewModel.retry() }
                Button("응답 지우기", role: .destructive) { viewModel.clearResponse() }
            }
        }
        .font(.caption)
    }

    private var responseArea: some View {
        ScrollView {
            Text(viewModel.responseText.isEmpty ? "응답이 여기에 표시됩니다." : viewModel.responseText)
                .font(.callout)
                .foregroundStyle(viewModel.responseText.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 120, maxHeight: 260)
    }

    private var applyButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let applied = viewModel.lastAppliedAction {
                Label("\(applied.displayName) 완료", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            HStack {
                Button("복사") { viewModel.copyResponseToClipboard() }
                Menu("적용") {
                    ForEach(AIApplyAction.allCases.filter { $0 != .panelOnly }) { action in
                        Button(action.displayName) { Task { await viewModel.apply(action) } }
                    }
                }
            }
            .font(.caption)
        }
    }
}
