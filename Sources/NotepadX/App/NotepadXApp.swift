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
        MenuBarExtra("Notepad", systemImage: "note.text", isInserted: $showsMenuBarItem) {
            Button("빠른 메모…") { QuickCaptureController.shared.show() }
                .keyboardShortcut("n", modifiers: [.control, .option])
            Button("Notepad 열기") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("종료") { NSApp.terminate(nil) }
        }

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
