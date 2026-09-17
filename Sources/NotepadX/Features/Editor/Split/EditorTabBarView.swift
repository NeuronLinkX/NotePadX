import AppKit
import SwiftUI

/// 브라우저 스타일 탭 바 (스펙: 다중 탭 지원). Cmd+T로 새 탭, Cmd+W로 활성 탭을 닫는다.
struct EditorTabBarView: View {
    @ObservedObject var tabsViewModel: OpenTabsViewModel
    @Binding var activeNoteID: UUID?

    private static let tabWidth: CGFloat = 150

    var body: some View {
        if !tabsViewModel.openNoteIDs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(Array(tabsViewModel.openNoteIDs.enumerated()), id: \.element) { index, id in
                        tab(for: id, index: index)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: tabsViewModel.openNoteIDs)
            }
            .frame(height: 32)
            .background(.bar)
        }
    }

    // 패키징된 .app에서만 SwiftUI onTapGesture/DragGesture가 간헐적으로 반응하지 않는
    // 현상이 있어, 탭 선택/닫기/드래그 재정렬을 모두 SwiftUI 제스처를 거치지 않고
    // AppKit NSView의 mouseDown/mouseDragged/mouseUp을 직접 받는 TabClickCatcher가
    // 처리한다. 위에 그려지는 텍스트/아이콘은 allowsHitTesting(false)로 순수 표시용으로만
    // 두고, 클릭·드래그 판정은 전부 이 뷰 하나가 좌표로 담당한다.
    @ViewBuilder
    private func tab(for id: UUID, index: Int) -> some View {
        let isActive = activeNoteID == id
        ZStack(alignment: .leading) {
            TabClickCatcher(
                index: index,
                tabCount: tabsViewModel.openNoteIDs.count,
                tabWidth: Self.tabWidth,
                onSelect: { activeNoteID = id },
                onClose: { closeTab(id) },
                onDragToTarget: { target in
                    guard let currentIndex = tabsViewModel.openNoteIDs.firstIndex(of: id) else { return }
                    guard currentIndex != target else { return }
                    tabsViewModel.moveTab(from: currentIndex, to: target)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                Text(tabsViewModel.titles[id] ?? "제목 없음")
                    .lineLimit(1)
                    .font(.caption)
                    .frame(width: 112, alignment: .leading)

                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .help("탭 닫기")
                    .accessibilityLabel("탭 닫기")
            }
            .padding(.horizontal, 10)
            .allowsHitTesting(false)
        }
        .frame(width: Self.tabWidth, height: 32)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func closeTab(_ id: UUID) {
        activeNoteID = tabsViewModel.closeTab(id, activeNoteID: activeNoteID)
    }
}

/// 탭 하나의 전체 영역을 덮는 투명 NSView. 오른쪽 끝 닫기(x) 아이콘 영역 안에서 손을 떼면
/// onClose, 드래그 없이 떼면 onSelect, 가로로 일정 거리 이상 끌면 드래그로 간주해 지나간
/// 탭 너비만큼마다 onDragToTarget으로 목표 인덱스를 알려준다. SwiftUI 제스처 인식기를
/// 전혀 거치지 않고 AppKit이 직접 마우스 이벤트를 넘겨주므로, SwiftUI 제스처 파이프라인
/// 자체의 문제와 무관하게 항상 동작한다.
private struct TabClickCatcher: NSViewRepresentable {
    let index: Int
    let tabCount: Int
    let tabWidth: CGFloat
    let onSelect: () -> Void
    let onClose: () -> Void
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
        nsView.onSelect = onSelect
        nsView.onClose = onClose
        nsView.onDragToTarget = onDragToTarget
    }

    final class CatcherView: NSView {
        var index = 0
        var tabCount = 1
        var tabWidth: CGFloat = 150
        var onSelect: (() -> Void)?
        var onClose: (() -> Void)?
        var onDragToTarget: ((Int) -> Void)?
        private let closeZoneWidth: CGFloat = 30

        private var dragStartPoint: NSPoint?
        private var dragOriginIndex: Int?
        /// 실수로 몇 픽셀 움직인 클릭까지 드래그로 잡으면 선택 자체가 씹힌 것처럼 보이므로,
        /// 탭 너비의 1/3을 넘는 확실한 이동에서만 재정렬을 시작한다.
        private var dragThreshold: CGFloat { tabWidth / 3 }

        override var isFlipped: Bool { true }

        // 선택/닫기는 mouseDown에서 즉시 실행한다(드래그 여부와 무관하게) — 이전에 확인된
        // 동작과 똑같이 유지해서, 드래그 재정렬을 얹다가 선택 자체가 깨지는 일이 없게 한다.
        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            FileHandle.standardError.write("[TABDEBUG] mouseDown index=\(index) point=\(point) bounds=\(bounds)\n".data(using: .utf8)!)
            if point.x > bounds.width - closeZoneWidth {
                onClose?()
            } else {
                onSelect?()
            }
            dragStartPoint = event.locationInWindow
            dragOriginIndex = index
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let result = super.hitTest(point)
            FileHandle.standardError.write("[TABDEBUG] hitTest index=\(index) point=\(point) result=\(String(describing: result))\n".data(using: .utf8)!)
            return result
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
    }
}

/// 임시 진단용 버튼. 탭이 열려 있는지 여부와 무관하게 항상 화면에 보이며, raw AppKit
/// mouseDown이 이 화면 영역까지 실제로 도달하는지만 확인한다. 문제를 진단한 뒤에는
/// 반드시 제거한다.
struct DiagnosticTestButton: NSViewRepresentable {
    func makeNSView(context: Context) -> DiagnosticView { DiagnosticView() }
    func updateNSView(_ nsView: DiagnosticView, context: Context) {}

    final class DiagnosticView: NSView {
        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            FileHandle.standardError.write("[TABDEBUG] DIAGNOSTIC BUTTON mouseDown point=\(point) bounds=\(bounds)\n".data(using: .utf8)!)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let result = super.hitTest(point)
            FileHandle.standardError.write("[TABDEBUG] DIAGNOSTIC BUTTON hitTest point=\(point) result=\(String(describing: result))\n".data(using: .utf8)!)
            return result
        }
    }
}
