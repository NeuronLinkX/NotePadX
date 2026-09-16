import SwiftUI

/// 브라우저 스타일 탭 바 (스펙: 다중 탭 지원). Cmd+T로 새 탭, Cmd+W로 활성 탭을 닫는다.
struct EditorTabBarView: View {
    @ObservedObject var tabsViewModel: OpenTabsViewModel
    @Binding var activeNoteID: UUID?

    var body: some View {
        if !tabsViewModel.openNoteIDs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabsViewModel.openNoteIDs, id: \.self) { id in
                        tab(for: id)
                    }
                }
            }
            .frame(height: 32)
            .background(.bar)
        }
    }

    @ViewBuilder
    private func tab(for id: UUID) -> some View {
        let isActive = activeNoteID == id
        HStack(spacing: 6) {
            Text(tabsViewModel.titles[id] ?? "제목 없음")
                .lineLimit(1)
                .font(.caption)
            Button {
                closeTab(id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("탭 닫기")
            .accessibilityLabel("탭 닫기")
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 90, maxWidth: 180, minHeight: 32)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { activeNoteID = id }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func closeTab(_ id: UUID) {
        activeNoteID = tabsViewModel.closeTab(id, activeNoteID: activeNoteID)
    }
}
