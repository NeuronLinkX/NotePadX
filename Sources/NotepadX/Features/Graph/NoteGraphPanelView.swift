import SwiftUI

/// "연관 메모" 패널. 태그를 붙이지 않아도 서로 비슷한 어휘를 쓰는 노트끼리 자동으로
/// 이어 보여준다(스펙: 신경망 이미지처럼 키워드로 서로 알아서 찾아 이어 붙이는 시뮬레이션).
/// AI 패널과 같은 자리에서 열고 닫을 수 있다.
struct NoteGraphPanelView: View {
    @ObservedObject var viewModel: NoteGraphViewModel
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("연관 메모").font(.headline)
                Spacer()
                if viewModel.isComputing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await viewModel.rebuild(canvasSize: canvasSize) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("다시 계산")
                .accessibilityLabel("연관 메모 다시 계산")
            }
            .padding(10)
            Divider()

            GeometryReader { proxy in
                ZStack {
                    graphCanvas

                    if viewModel.nodes.isEmpty && !viewModel.isComputing {
                        ContentUnavailableView(
                            "연관된 메모가 아직 없어요",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("메모 본문이 비슷한 단어를 쓸수록 자동으로 이어져요.")
                        )
                    }
                }
                .onAppear {
                    canvasSize = proxy.size
                    Task { await viewModel.rebuild(canvasSize: proxy.size) }
                }
                .onChange(of: proxy.size) { _, newSize in canvasSize = newSize }
            }
        }
        .frame(width: 300)
        .background(.regularMaterial)
    }

    private var graphCanvas: some View {
        Canvas { context, _ in
            let positionByID = Dictionary(uniqueKeysWithValues: viewModel.nodes.map { ($0.id, $0.position) })
            for edge in viewModel.edges {
                guard let from = positionByID[edge.from], let to = positionByID[edge.to] else { continue }
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(
                    path,
                    with: .color(.accentColor.opacity(0.12 + edge.weight * 0.5)),
                    lineWidth: 1 + edge.weight * 2.5
                )
            }
            for node in viewModel.nodes {
                let dotRect = CGRect(x: node.position.x - 4, y: node.position.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dotRect), with: .color(.accentColor))
            }
        }
        .overlay {
            ForEach(viewModel.nodes) { node in
                Text(node.title)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .frame(maxWidth: 74)
                    .fixedSize(horizontal: false, vertical: true)
                    .position(x: node.position.x, y: node.position.y + 12)
            }
        }
    }
}
