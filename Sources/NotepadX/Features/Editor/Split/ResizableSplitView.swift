import AppKit
import SwiftUI

/// 드래그로 비율을 바꿀 수 있는 좌우/상하 2단 컨테이너 (스펙 9절 "분할 비율은 드래그로 변경").
/// NavigationSplitView는 바깥쪽 3열 레이아웃에 이미 쓰고 있어서, 에디터 영역 내부의
/// 자유로운 분할에는 별도의 가벼운 구현을 쓴다.
struct ResizableSplitView<First: View, Second: View>: View {
    let axis: Axis
    @Binding var ratio: Double
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    @State private var dragStartRatio: Double?

    private let minimumFraction = 0.2
    private let dividerThickness: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let totalLength = axis == .horizontal ? geometry.size.width : geometry.size.height
            let firstLength = max(totalLength * ratio - dividerThickness / 2, 0)
            let secondLength = max(totalLength - firstLength - dividerThickness, 0)

            Group {
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        first().frame(width: firstLength)
                        divider(totalLength: totalLength)
                        second().frame(width: secondLength)
                    }
                } else {
                    VStack(spacing: 0) {
                        first().frame(height: firstLength)
                        divider(totalLength: totalLength)
                        second().frame(height: secondLength)
                    }
                }
            }
        }
    }

    private func divider(totalLength: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: axis == .horizontal ? dividerThickness : nil, height: axis == .vertical ? dividerThickness : nil)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard totalLength > 0 else { return }
                        if dragStartRatio == nil { dragStartRatio = ratio }
                        guard let start = dragStartRatio else { return }
                        let translation = axis == .horizontal ? value.translation.width : value.translation.height
                        let newRatio = start + translation / totalLength
                        ratio = min(max(newRatio, minimumFraction), 1 - minimumFraction)
                    }
                    .onEnded { _ in dragStartRatio = nil }
            )
    }
}
