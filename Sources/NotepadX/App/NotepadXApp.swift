import SwiftUI

@main
struct NotepadXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appearanceStore = AppearanceSettingsStore()
    @StateObject private var menuBarVisibility = MenuBarVisibility()

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
        MenuBarExtra("Notepad", systemImage: "note.text", isInserted: $menuBarVisibility.isInserted) {
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

/// 메뉴 막대 아이콘을 보일지 여부. MenuBarExtra의 isInserted에 App 구조체의 @AppStorage를 바로 물리면
/// 메뉴가 끝없이 다시 그려져 CPU를 100% 쓰며 창이 멈추므로, 값이 실제로 바뀔 때만 알리는 객체로 감싼다.
@MainActor
private final class MenuBarVisibility: ObservableObject {
    @Published var isInserted: Bool {
        didSet {
            guard isInserted != oldValue, isInserted != defaults.bool(forKey: Self.key) else { return }
            defaults.set(isInserted, forKey: Self.key)
        }
    }

    private static let key = QuickCaptureController.menuBarEnabledKey
    private let defaults = AppConfig.defaults
    private var observer: NSObjectProtocol?

    init() {
        isInserted = AppConfig.defaults.bool(forKey: Self.key)
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let stored = self.defaults.bool(forKey: Self.key)
                if stored != self.isInserted { self.isInserted = stored }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
