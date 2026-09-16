import Foundation

/// 외모 설정(라이트/다크/시스템 동기화, 색상 테마)을 UserDefaults에 저장한다.
/// 창(WindowGroup)과 설정(Settings) 씬이 같은 인스턴스를 공유해서, 설정에서 바꾸면
/// 열려 있는 창에도 바로 반영된다.
@MainActor
final class AppearanceSettingsStore: ObservableObject {
    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey) }
    }
    @Published var colorTheme: ColorTheme {
        didSet { UserDefaults.standard.set(colorTheme.rawValue, forKey: Self.colorThemeKey) }
    }

    private static let appearanceModeKey = "NotepadX.appearanceMode"
    private static let colorThemeKey = "NotepadX.colorTheme"

    init() {
        let defaults = UserDefaults.standard
        appearanceMode = defaults.string(forKey: Self.appearanceModeKey).flatMap(AppearanceMode.init) ?? .system
        colorTheme = defaults.string(forKey: Self.colorThemeKey).flatMap(ColorTheme.init) ?? .classic
    }
}
