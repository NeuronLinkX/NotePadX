import SwiftUI

@main
struct NotepadXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(AppConfig.displayName) {
            RootView()
        }
        .commands {
            AppCommands()
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        // 스펙 16절: 설정 화면에 AI 탭을 둔다. 지금은 AI 탭 하나뿐이라 TabView 없이 바로 보여준다.
        Settings {
            AISettingsView(viewModel: AISettingsViewModel())
        }
    }
}
