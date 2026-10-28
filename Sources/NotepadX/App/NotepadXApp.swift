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

        // 설정 화면: 다크 모드/색상 테마를 고르는 모양 탭 등.
        Settings {
            TabView {
                AppearanceSettingsView(store: appearanceStore)
                    .tabItem { Label("모양", systemImage: "paintbrush") }
                BackupSettingsView()
                    .tabItem { Label("백업", systemImage: "externaldrive.badge.timemachine") }
                SecuritySettingsView()
                    .tabItem { Label("보안", systemImage: "lock.shield") }
                IntegrationSettingsView()
                    .tabItem { Label("연동", systemImage: "square.and.arrow.up.on.square") }
            }
        }
    }
}
