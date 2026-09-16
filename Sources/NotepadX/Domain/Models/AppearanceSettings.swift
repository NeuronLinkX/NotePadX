import SwiftUI

/// 시스템 테마와 동기화하거나 밝게/어둡게를 직접 고른다.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "시스템 설정과 동기화"
        case .light: return "밝게"
        case .dark: return "어둡게"
        }
    }

    /// nil을 돌려주면 SwiftUI가 시스템 설정을 그대로 따른다.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 디자인된 색상 테마. 사이드바 강조색과 선택 표시 등 앱 곳곳의 강조색을 함께 바꾼다.
enum ColorTheme: String, CaseIterable, Identifiable, Codable {
    case classic
    case rabbit
    case turtle
    case monkey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "기본"
        case .rabbit: return "토끼 테마"
        case .turtle: return "거북이 테마"
        case .monkey: return "원숭이 테마"
        }
    }

    var emoji: String {
        switch self {
        case .classic: return "⬤"
        case .rabbit: return "🐰"
        case .turtle: return "🐢"
        case .monkey: return "🐵"
        }
    }

    /// 앱 전역 강조색(버튼, 선택 표시, 링크 등).
    var accentColor: Color {
        switch self {
        case .classic: return .accentColor
        case .rabbit: return Color(red: 1.0, green: 0.55, blue: 0.66) // 산호빛 분홍
        case .turtle: return Color(red: 0.20, green: 0.55, blue: 0.42) // 이끼빛 초록
        case .monkey: return Color(red: 0.78, green: 0.51, blue: 0.24) // 캐러멜 갈색
        }
    }
}
