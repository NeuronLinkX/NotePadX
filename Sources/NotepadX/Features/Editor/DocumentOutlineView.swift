import SwiftUI

/// 문서 개요 트리 한 노드. 사이드바의 `FolderTreeNode`와 같은 모양(OutlineGroup에 바로
/// 넘길 수 있는 재귀 구조)이다.
struct HeadingOutlineNode: Identifiable {
    let item: HeadingOutlineItem
    var children: [HeadingOutlineNode]
    var id: Int { item.pos }
    var childrenOrNil: [HeadingOutlineNode]? { children.isEmpty ? nil : children }
}

enum HeadingOutlineBuilder {
    /// 평평한 제목 목록(문서 순서)을 레벨 기준으로 중첩 트리로 바꾼다. 예를 들어 H1 다음에
    /// 바로 H3가 나오면(H2를 건너뛰어도) H3는 그 H1의 자식이 된다 — VS Code/Word의 개요
    /// 창과 같은 흔한 규칙이다.
    static func buildTree(from headings: [HeadingOutlineItem]) -> [HeadingOutlineNode] {
        final class MutableNode {
            let item: HeadingOutlineItem
            var children: [MutableNode] = []
            init(item: HeadingOutlineItem) { self.item = item }
            func frozen() -> HeadingOutlineNode {
                HeadingOutlineNode(item: item, children: children.map { $0.frozen() })
            }
        }

        var roots: [MutableNode] = []
        var stack: [MutableNode] = []
        for heading in headings {
            let node = MutableNode(item: heading)
            while let last = stack.last, last.item.level >= heading.level {
                stack.removeLast()
            }
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                roots.append(node)
            }
            stack.append(node)
        }
        return roots.map { $0.frozen() }
    }
}

/// 편집기 왼쪽에 붙는 문서 개요 패널. 제목(H1~H6)을 계층으로 보여주고, 클릭하면 그
/// 위치로 스크롤한다 — 긴 문서에서 목차 삼아 빠르게 이동하기 위함이다.
struct DocumentOutlineView: View {
    @ObservedObject var viewModel: EditorViewModel

    private var tree: [HeadingOutlineNode] {
        HeadingOutlineBuilder.buildTree(from: viewModel.headingOutline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("개요")
                    .font(.headline)
                Spacer()
                Button { viewModel.isShowingOutline = false } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("개요 닫기")
                .accessibilityLabel("개요 닫기")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if viewModel.headingOutline.isEmpty {
                ContentUnavailableView(
                    "제목이 없습니다",
                    systemImage: "list.bullet.indent",
                    description: Text("문서에 제목(1~6)을 추가하면 여기에 목차로 나타납니다.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    OutlineGroup(tree, children: \.childrenOrNil) { node in
                        Text(node.item.text.trimmingCharacters(in: .whitespaces).isEmpty ? "제목 없음" : node.item.text)
                            .font(headingFont(for: node.item.level))
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.scrollToHeading(node.item) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(width: 220)
        .background(.regularMaterial)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .body.weight(.semibold)
        case 2: return .body
        default: return .callout
        }
    }
}
