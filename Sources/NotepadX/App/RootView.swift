import SwiftUI

/// 데이터베이스 부트스트랩이 끝나기 전까지 로딩 화면을 보여주고,
/// 실패하면 원인과 재시도 버튼을 보여준다 (스펙 23절: stack trace 대신 사용자 조치 안내).
struct RootView: View {
    @State private var environment: AppEnvironment?
    @State private var bootstrapError: AppError?
    /// 위젯에서 앱이 막 켜지는 경우 URL 이벤트가 부트스트랩보다 먼저 오므로, ContentView가
    /// 만들어질 때까지 라우터가 보관해 뒀다가 넘긴다.
    @ObservedObject private var deepLinkRouter = WidgetDeepLinkRouter.shared

    var body: some View {
        Group {
            if let environment {
                ContentView(environment: environment, pendingDeepLink: $deepLinkRouter.pending)
                    .environmentObject(environment)
                    .modifier(IntegrityAlert(environment: environment))
            } else if let bootstrapError {
                BootstrapErrorView(error: bootstrapError, retry: bootstrap)
            } else {
                ProgressView("Notepad를 준비하는 중…")
                    .frame(minWidth: 480, minHeight: 320)
            }
        }
        .task {
            if environment == nil { bootstrap() }
        }
    }

    private func bootstrap() {
        bootstrapError = nil
        Task {
            do {
                environment = try await AppEnvironment.bootstrap()
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

/// 시작 후 점검에서 데이터베이스 문제가 발견되면 알린다. 자동 백업은 이미 멈춘 상태다.
private struct IntegrityAlert: ViewModifier {
    @ObservedObject var environment: AppEnvironment

    func body(content: Content) -> some View {
        content.alert("데이터 점검에서 문제가 발견되었습니다", isPresented: Binding(
            get: { environment.integrityProblem != nil },
            set: { if !$0 { environment.integrityProblem = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("""
            메모 데이터베이스 구조에 이상이 있을 수 있습니다. 새 메모를 계속 쓰기 전에 설정 > 백업에서 \
            가장 최근의 정상 백업으로 복원할 수 있습니다. (이상이 해결될 때까지 자동 백업은 멈춰 둡니다.)

            \(environment.integrityProblem ?? "")
            """)
        }
    }
}
