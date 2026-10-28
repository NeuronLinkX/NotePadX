import SwiftUI

@main
struct NotepadXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearanceStore = AppearanceSettingsStore()
    @AppStorage(QuickCaptureController.menuBarEnabledKey, store: AppConfig.defaults) private var showsMenuBarItem = false

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

        // 메뉴 막대 아이콘(설정 > 연동에서 켜고 끈다). 창이 하나도 없어도 빠른 메모를 열 수 있다.
        MenuBarExtra("NotepadX", systemImage: "note.text", isInserted: $showsMenuBarItem) {
            Button("빠른 메모…") { QuickCaptureController.shared.show() }
                .keyboardShortcut("n", modifiers: [.control, .option])
            Button("NotepadX 열기") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("종료") { NSApp.terminate(nil) }
        }

        // 스펙 16절: 설정 화면에 AI 탭, 그리고 다크 모드/색상 테마를 고르는 모양 탭을 둔다.
        Settings {
            TabView {
                AISettingsContainer()
                    .tabItem { Label("AI", systemImage: "sparkles") }
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

/// 설정 창이 실제로 열릴 때 비로소 AISettingsViewModel을 만든다. 뷰모델 init이 Keychain에서
/// API 키를 읽는데, App.body 안에서 바로 만들면 앱을 켤 때마다(설정을 열지도 않았는데)
/// Keychain 접근 허용 창이 뜰 때까지 메인 스레드가 멈춰서 창조차 안 뜬다.
private struct AISettingsContainer: View {
    @StateObject private var viewModel = AISettingsViewModel()

    var body: some View {
        AISettingsView(viewModel: viewModel)
    }
}
