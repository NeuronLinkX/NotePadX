import SwiftUI

@main
struct NotepadXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearanceStore = AppearanceSettingsStore()

    var body: some Scene {
        WindowGroup(AppConfig.displayName) {
            RootView()
                .environmentObject(appearanceStore)
                .preferredColorScheme(appearanceStore.appearanceMode.colorScheme)
                .tint(appearanceStore.colorTheme.accentColor)
        }
        .commands {
            AppCommands()
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        // 스펙 16절: 설정 화면에 AI 탭, 그리고 다크 모드/색상 테마를 고르는 모양 탭을 둔다.
        Settings {
            TabView {
                AISettingsContainer()
                    .tabItem { Label("AI", systemImage: "sparkles") }
                AppearanceSettingsView(store: appearanceStore)
                    .tabItem { Label("모양", systemImage: "paintbrush") }
            }
        }
    }
}

/// 설정 창이 실제로 열릴 때 비로소 AISettingsViewModel을 만든다. 뷰모델 init이 Keychain에서
/// API 키를 읽는데, App.body 안에서 바로 만들면 앱을 켤 때마다(설정을 열지도 않았는데)
/// Keychain 접근 허용 창이 뜰 때까지 메인 스레드가 멈춰서 창조차 안 뜬다.
private struct AISettingsContainer: View {
    @StateObject private var viewModel = AISettingsViewModel()

    var body: some View {
        AISettingsView(viewModel: viewModel)
    }
}
