import SwiftUI

/// 스펙 9절 분할 편집 모드. LLM 결과 패널(한쪽 편집기 + 한쪽 LLM 결과)은 Phase 7에서
/// LLM 패널 자체가 생기면 추가한다 — 지금은 그 기능이 없어 옵션에 넣지 않는다.
enum SplitMode: String, CaseIterable, Sendable {
    case none
    case horizontal // 좌우 2단
    case vertical   // 상하 2단

    var isSplit: Bool { self != .none }

    /// ResizableSplitView에 그대로 넘기는 SwiftUI Axis. .none일 때는 사용하지 않는다.
    var axis: Axis {
        self == .vertical ? .vertical : .horizontal
    }
}
