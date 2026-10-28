import AppKit
import SwiftUI

/// 브라우저 스타일 탭 바 (스펙: 다중 탭 지원). Cmd+T로 새 탭, Cmd+W로 활성 탭을 닫고,
/// Cmd+Shift+[ / ]로 이웃 탭으로 옮긴다.
struct EditorTabBarView: View {
    @ObservedObject var tabsViewModel: OpenTabsViewModel
    @Binding var activeNoteID: UUID?
    var onNewTab: (() -> Void)?

    /// 글자 크기 설정(접근성 텍스트 크기)에 맞춰 같이 커지고 작아진다.
    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 34
    @State private var hoveredID: UUID?

    static let minTabWidth: CGFloat = 96
    static let maxTabWidth: CGFloat = 220
    static let tabSpacing: CGFloat = 1
    static let newTabButtonWidth: CGFloat = 36

    /// 탭이 적으면 넉넉하게(최대폭), 많아지면 창 너비에 맞춰 줄이다가 최소폭 밑으로는
    /// 내려가지 않는다 — 그 이상은 가로 스크롤.
    static func tabWidth(count: Int, available: CGFloat) -> CGFloat {
        guard count > 0 else { return maxTabWidth }
        let spacing = tabSpacing * CGFloat(count - 1)
        return min(maxTabWidth, max(minTabWidth, (available - spacing) / CGFloat(count)))
    }

    var body: some View {
        if !tabsViewModel.openNoteIDs.isEmpty {
            GeometryReader { proxy in
                let reserved = onNewTab == nil ? 0 : Self.newTabButtonWidth
                let width = Self.tabWidth(count: tabsViewModel.openNoteIDs.count, available: proxy.size.width - reserved)
                HStack(spacing: 0) {
                    ScrollViewReader { reader in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Self.tabSpacing) {
                                ForEach(Array(tabsViewModel.openNoteIDs.enumerated()), id: \.element) { index, id in
                                    tab(for: id, index: index, width: width).id(id)
                                }
                            }
                            .animation(.easeInOut(duration: 0.15), value: tabsViewModel.openNoteIDs)
                        }
                        .onChange(of: activeNoteID) { _, id in
                            guard let id else { return }
                            withAnimation(.easeInOut(duration: 0.15)) { reader.scrollTo(id, anchor: .center) }
                        }
                    }
                    if let onNewTab { newTabButton(action: onNewTab) }
                }
            }
            .frame(height: barHeight)
            // 기본값(.all)이면 배경이 툴바 영역(safe area)까지 번져서 탭이 실제보다 훨씬
            // 커 보인다.
            .background(.bar, ignoresSafeAreaEdges: [])
        }
    }

    // 패키징된 .app에서만 SwiftUI onTapGesture/DragGesture가 간헐적으로 반응하지 않는
    // 현상이 있어, 탭 선택/닫기/드래그 재정렬을 모두 SwiftUI 제스처를 거치지 않고
    // AppKit NSView의 mouseDown/mouseDragged/mouseUp을 직접 받는 TabClickCatcher가
    // 처리한다. 위에 그려지는 텍스트/아이콘은 allowsHitTesting(false)로 순수 표시용으로만
    // 두고, 클릭·드래그 판정은 전부 이 뷰 하나가 좌표로 담당한다.
    @ViewBuilder
    private func tab(for id: UUID, index: Int, width: CGFloat) -> some View {
        let isActive = activeNoteID == id
        let isHovered = hoveredID == id
        let showsClose = isActive || isHovered
        let title = tabsViewModel.titles[id] ?? "제목 없음"

        ZStack(alignment: .leading) {
            TabClickCatcher(
                index: index,
                tabCount: tabsViewModel.openNoteIDs.count,
                tabWidth: width,
                title: title,
                showsClose: showsClose,
                onSelect: { activeNoteID = id },
                onClose: { closeTab(id) },
                onHoverChanged: { hovering in
                    if hovering {
                        hoveredID = id
                    } else if hoveredID == id {
                        hoveredID = nil
                    }
                },
                onDragToTarget: { target in
                    guard let currentIndex = tabsViewModel.openNoteIDs.firstIndex(of: id) else { return }
                    guard currentIndex != target else { return }
                    tabsViewModel.moveTab(from: currentIndex, to: target)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.caption.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .opacity(showsClose ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .allowsHitTesting(false)
        }
        .frame(width: width, height: barHeight)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 7)
                .fill(isActive ? Color.accentColor.opacity(0.16) : (isHovered ? Color.primary.opacity(0.07) : Color.clear))
        }
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func newTabButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.newTabButtonWidth, height: barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("새 탭 (⌘T)")
        .accessibilityLabel("새 탭")
    }

    private func closeTab(_ id: UUID) {
        activeNoteID = tabsViewModel.closeTab(id, activeNoteID: activeNoteID)
    }
}

/// 탭 하나의 전체 영역을 덮는 투명 NSView. 오른쪽 끝 닫기(x) 아이콘 영역을 누르면 onClose
/// (아이콘이 보일 때만), 그 밖은 onSelect, 가로로 일정 거리 이상 끌면 드래그로 간주해 지나간
/// 탭 너비만큼마다 onDragToTarget으로 목표 인덱스를 알려준다. 휠 클릭은 닫기. SwiftUI
/// 제스처 인식기를 전혀 거치지 않고 AppKit이 직접 마우스 이벤트를 넘겨주므로, SwiftUI
/// 제스처 파이프라인 자체의 문제와 무관하게 항상 동작한다.
private struct TabClickCatcher: NSViewRepresentable {
    let index: Int
    let tabCount: Int
    let tabWidth: CGFloat
    let title: String
    let showsClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onDragToTarget: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.index = index
        nsView.tabCount = tabCount
        nsView.tabWidth = tabWidth
        nsView.title = title
        nsView.showsClose = showsClose
        nsView.toolTip = title
        nsView.onSelect = onSelect
        nsView.onClose = onClose
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragToTarget = onDragToTarget
    }

    final class CatcherView: NSView {
        var index = 0
        var tabCount = 1
        var tabWidth: CGFloat = 150
        var title = ""
        var showsClose = false
        var onSelect: (() -> Void)?
        var onClose: (() -> Void)?
        var onHoverChanged: ((Bool) -> Void)?
        var onDragToTarget: ((Int) -> Void)?
        private let closeZoneWidth: CGFloat = 30

        private var dragStartPoint: NSPoint?
        private var dragOriginIndex: Int?
        /// 실수로 몇 픽셀 움직인 클릭까지 드래그로 잡으면 선택 자체가 씹힌 것처럼 보이므로,
        /// 탭 너비의 1/3을 넘는 확실한 이동에서만 재정렬을 시작한다.
        private var dragThreshold: CGFloat { tabWidth / 3 }

        override var isFlipped: Bool { true }

        // 창이 맨 앞이 아닐 때 탭을 클릭하면, 기본값으로는 그 첫 클릭이 창을 활성화만 시키고
        // 실제 클릭 동작(선택/닫기)은 무시된다 — "됐다 안됐다" 하던 원인. 이 뷰는 첫 클릭부터
        // 바로 반응해야 하므로 명시적으로 true를 돌려준다.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
        override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }

        // 선택/닫기는 mouseDown에서 즉시 실행한다(드래그 여부와 무관하게) — 이전에 확인된
        // 동작과 똑같이 유지해서, 드래그 재정렬을 얹다가 선택 자체가 깨지는 일이 없게 한다.
        // 닫기 아이콘이 안 보이는 상태(비활성 + 마우스가 안 올라온 탭)에서는 그 자리를
        // 눌러도 닫지 않고 선택한다.
        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if showsClose, point.x > bounds.width - closeZoneWidth {
                onClose?()
            } else {
                onSelect?()
            }
            dragStartPoint = event.locationInWindow
            dragOriginIndex = index
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStartPoint, let originIndex = dragOriginIndex else { return }
            let translationX = event.locationInWindow.x - start.x
            guard abs(translationX) > dragThreshold else { return }
            let shift = Int((translationX / tabWidth).rounded())
            let target = min(max(originIndex + shift, 0), tabCount - 1)
            onDragToTarget?(target)
        }

        override func mouseUp(with event: NSEvent) {
            dragStartPoint = nil
            dragOriginIndex = nil
        }

        // 휠(가운데) 버튼 클릭으로 탭 닫기 — 브라우저와 같은 동작.
        override func otherMouseUp(with event: NSEvent) {
            if event.buttonNumber == 2 { onClose?() }
        }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { title.isEmpty ? "탭" : "탭: \(title)" }
        override func accessibilityPerformPress() -> Bool {
            onSelect?()
            return true
        }
    }
}
