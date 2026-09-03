import SwiftUI

/// 데이터베이스 부트스트랩이 끝나기 전까지 로딩 화면을 보여주고,
/// 실패하면 원인과 재시도 버튼을 보여준다 (스펙 23절: stack trace 대신 사용자 조치 안내).
struct RootView: View {
    @State private var environment: AppEnvironment?
    @State private var bootstrapError: AppError?
    @State private var isShowingMissingAPIKeyWarning = false

    var body: some View {
        Group {
            if let environment {
                ContentView(environment: environment)
                    .environmentObject(environment)
            } else if let bootstrapError {
                BootstrapErrorView(error: bootstrapError, retry: bootstrap)
            } else {
                ProgressView("NotepadX를 준비하는 중…")
                    .frame(minWidth: 480, minHeight: 320)
            }
        }
        .task {
            if environment == nil { bootstrap() }
        }
        .alert("OpenAI API 키가 없습니다", isPresented: $isShowingMissingAPIKeyWarning) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("AI 기능을 쓰려면 설정 > AI 탭에서 키를 한 번 등록하세요. 등록하면 계속 유지됩니다.")
        }
    }

    private func bootstrap() {
        bootstrapError = nil
        Task {
            do {
                let bootstrapped = try await AppEnvironment.bootstrap()
                environment = bootstrapped
                // 스펙: 등록된 API 키(Keychain, 없으면 OPENAI_API_KEY 환경 변수)가 없으면 최초 진입 시 한 번 알린다.
                isShowingMissingAPIKeyWarning = !LLMUseCase().hasAPIKey()
            } catch let error as AppError {
                bootstrapError = error
            } catch {
                bootstrapError = .databaseFailure(error.localizedDescription)
            }
        }
    }
}

private struct BootstrapErrorView: View {
    let error: AppError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.errorDescription ?? "알 수 없는 오류가 발생했습니다.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("다시 시도", action: retry)
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 320)
    }
}
