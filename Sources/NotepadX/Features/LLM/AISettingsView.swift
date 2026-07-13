import SwiftUI

/// 설정 > AI 탭 (스펙 16절). API 키는 앱 안에서 입력받거나 저장하지 않는다 — 오직
/// `OPENAI_API_KEY` 환경 변수를 읽기만 하는 읽기 전용 상태 표시다.
struct AISettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        Form {
            Section("Provider") {
                Picker("API Provider", selection: $viewModel.settings.provider) {
                    ForEach(AIProvider.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("인증 방식", selection: $viewModel.settings.authenticationMode) {
                    Text("개인 API 키(BYOK)").tag(AIAuthenticationMode.bringYourOwnKey)
                    Text("백엔드 프록시 (준비 중)").tag(AIAuthenticationMode.backendProxy)
                }
                .disabled(true)
                .help("백엔드 프록시 모드는 아직 서버가 없어 비활성화되어 있습니다.")
            }

            Section("API 키") {
                if viewModel.hasAPIKey {
                    HStack {
                        Text(viewModel.maskedKey ?? "설정됨")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Label("환경 변수로 등록됨", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("환경 변수가 등록되어 있지 않습니다", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("터미널에서 아래처럼 \(AISettingsViewModel.environmentVariableName)을 등록하고 앱을 다시 시작하세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("export \(AISettingsViewModel.environmentVariableName)=\"sk-...\"")
                            .font(.system(.caption, design: .monospaced))
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                    }
                }
            }

            Section("모델") {
                TextField("모델 ID", text: $viewModel.settings.modelID)
                    .onSubmit { viewModel.saveSettings() }
                TextField("API Base URL", text: $viewModel.settings.baseURLString)
                    .onSubmit { viewModel.saveSettings() }
            }

            Section("요청 설정") {
                LabeledContent("Timeout") {
                    Stepper(value: $viewModel.settings.timeoutSeconds, in: 10...300, step: 10) {
                        Text("\(Int(viewModel.settings.timeoutSeconds))초")
                    }
                }
                LabeledContent("Temperature") {
                    Slider(value: $viewModel.settings.temperature, in: 0...2, step: 0.1) {
                        Text("Temperature")
                    }
                    Text(String(format: "%.1f", viewModel.settings.temperature)).monospacedDigit()
                }
                LabeledContent("최대 출력 길이") {
                    Stepper(value: $viewModel.settings.maxOutputTokens, in: 128...8192, step: 128) {
                        Text("\(viewModel.settings.maxOutputTokens) 토큰")
                    }
                }
            }

            Section("사용자 정의 지침") {
                TextEditor(text: $viewModel.settings.systemInstruction)
                    .frame(height: 60)
                Text("모든 AI 요청의 시스템 메시지에 추가로 덧붙습니다. 문서 내용과는 항상 분리되어 전달됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button {
                        Task { await viewModel.testConnection() }
                    } label: {
                        if viewModel.isTestingConnection {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("연결 테스트")
                        }
                    }
                    .disabled(viewModel.isTestingConnection || !viewModel.hasAPIKey)

                    if let message = viewModel.testResultMessage {
                        Label(message, systemImage: viewModel.testSucceeded == true ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(viewModel.testSucceeded == true ? .green : .red)
                            .font(.caption)
                    }
                }
                if !viewModel.hasAPIKey {
                    Text("연결 테스트를 하려면 먼저 \(AISettingsViewModel.environmentVariableName) 환경 변수를 등록하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .onChange(of: viewModel.settings) { _, _ in viewModel.saveSettings() }
        .alert("오류", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
