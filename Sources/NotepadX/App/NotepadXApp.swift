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
                AISettingsView(viewModel: AISettingsViewModel())
                    .tabItem { Label("AI", systemImage: "sparkles") }
                AppearanceSettingsView(store: appearanceStore)
                    .tabItem { Label("모양", systemImage: "paintbrush") }
            }
        }
    }
}
