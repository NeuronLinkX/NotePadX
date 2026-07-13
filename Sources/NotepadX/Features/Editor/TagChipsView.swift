import SwiftUI

/// 제목 아래에 현재 노트의 태그를 칩으로 보여주고, "+"로 기존 태그를 추가하거나
/// 새 태그를 즉석에서 만들 수 있게 한다.
struct TagChipsView: View {
    @ObservedObject var viewModel: EditorViewModel
    let availableTags: [Tag]

    @State private var isShowingTagMenu = false
    @State private var newTagName = ""

    var body: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.noteTags) { tag in
                HStack(spacing: 4) {
                    Text(tag.name)
                    Button {
                        Task { await viewModel.removeTag(tag) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("\(tag.name) 태그 제거")
                    .accessibilityLabel("\(tag.name) 태그 제거")
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }

            Menu {
                let remaining = availableTags.filter { candidate in !viewModel.noteTags.contains { $0.id == candidate.id } }
                if !remaining.isEmpty {
                    ForEach(remaining) { tag in
                        Button(tag.name) { Task { await viewModel.addTag(tag) } }
                    }
                    Divider()
                }
                Button("새 태그 만들기…") { isShowingTagMenu = true }
            } label: {
                Image(systemName: "tag.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("태그 추가")
            .accessibilityLabel("태그 추가")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .alert("새 태그", isPresented: $isShowingTagMenu) {
            TextField("태그 이름", text: $newTagName)
            Button("취소", role: .cancel) {}
            Button("추가") {
                // Task{} 클로저는 나중에 실행되므로, 여기서 먼저 값을 지역 변수로 떼어내지 않으면
                // 바로 다음 줄의 newTagName = ""가 먼저 반영되어 빈 이름으로 태그가 만들어진다.
                let name = newTagName
                newTagName = ""
                Task { await viewModel.createAndAddTag(name: name) }
            }
        }
    }
}
