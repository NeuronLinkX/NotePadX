import Foundation

/// 분할된 패널 하나가 편집기인지 읽기 전용 미리보기인지 (스펙 9절 "한쪽 편집기, 한쪽 미리보기").
enum PaneDisplayMode: String, Sendable {
    case edit
    case preview
}
