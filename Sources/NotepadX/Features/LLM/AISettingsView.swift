import SwiftUI

/// 설정 > AI 탭 (스펙 16절). API 키는 여기서 입력받아 Keychain에 등록해 고정하거나
/// (`OPENAI_API_KEY` 환경 변수는 그 값이 없을 때만 쓰는 폴백이다), 등록된 값을 지울 수 있다.
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
                        Label(
                            viewModel.apiKeySource == .keychain ? "Keychain에 고정됨" : "환경 변수로 등록됨",
                            systemImage: viewModel.apiKeySource == .keychain ? "lock.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.green)
                    }
                    if viewModel.apiKeySource == .keychain {
                        Text("한 번 등록해 두면 앱을 다시 실행하거나 로그아웃해도 초기화되지 않습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("키 삭제", role: .destructive) { viewModel.clearStoredAPIKey() }
                    } else {
                        Text("환경 변수는 재부팅하거나 로그아웃하면 사라질 수 있습니다. 아래에서 한 번 등록해 두면 계속 초기화하지 않아도 됩니다.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        apiKeyRegistrationField
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("등록된 API 키가 없습니다", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("아래에 키를 입력하고 등록하면 Keychain에 안전하게 고정되어, 다시 설정할 필요가 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    apiKeyRegistrationField
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
                    Text("연결 테스트를 하려면 먼저 위에서 API 키를 등록하세요.")
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

    /// 물리적인 "등록" 버튼 — 여기서 누른 값만 Keychain에 고정되고, 지우기 전까지는
    /// 다시 바뀌지 않는다.
    private var apiKeyRegistrationField: some View {
        HStack {
            SecureField("sk-...", text: $viewModel.apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.registerAPIKey() }
            Button("키 등록") { viewModel.registerAPIKey() }
                .disabled(viewModel.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
