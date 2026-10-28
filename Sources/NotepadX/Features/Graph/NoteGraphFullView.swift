import SwiftUI

/// "연관 메모"를 독립된(크기 조절·최대화 가능한) macOS 창에 꽉 채워 보여준다
/// (스펙: 좁은 사이드 패널 대신 화면 전체를 볼 수 있게). 창은 NoteGraphWindowPresenter가 연다.
struct NoteGraphFullView: View {
    @ObservedObject var viewModel: NoteGraphViewModel
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("연관 메모").font(.title3.bold())
                Spacer()
                if viewModel.isComputing {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await viewModel.rebuild(canvasSize: canvasSize) }
                } label: {
                    Label("다시 계산", systemImage: "arrow.clockwise")
                }
            }
            .padding(14)
            Divider()

            GeometryReader { proxy in
                ZStack {
                    NoteGraph3DView(viewModel: viewModel)

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
                    viewModel.markVisible()
                    Task { await viewModel.rebuild(canvasSize: proxy.size) }
                }
                .onChange(of: proxy.size) { _, newSize in canvasSize = newSize }
                .onDisappear {
                    viewModel.markHidden()
                }
            }
        }
        .background(Color.white)
        .frame(minWidth: 560, minHeight: 420)
    }
}
