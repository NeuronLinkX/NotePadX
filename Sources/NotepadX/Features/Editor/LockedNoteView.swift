import SwiftUI

/// 잠긴 메모를 열기 전에 보여주는 화면. 내용은 이 뷰가 만들어지기 전에도, 이후에도(인증 전까지) 어디에도
/// 그려지지 않는다 — 편집기(WKWebView) 자체를 만들지 않기 때문이다.
struct LockedNoteView: View {
    let title: String
    /// 인증을 시도하고, 통과했으면 true.
    let onUnlock: () async -> Bool

    @State private var isAuthenticating = false
    @State private var didFail = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("이 메모는 잠겨 있습니다")
                .foregroundStyle(.secondary)

            Button {
                Task { await attempt() }
            } label: {
                Label("Touch ID 또는 암호로 열기", systemImage: "touchid")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isAuthenticating)

            if didFail {
                Text("인증하지 못했습니다. 다시 시도해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 메모를 선택하자마자 인증 창이 바로 뜨게 한다(취소하면 위 버튼으로 다시 시도).
        .task { await attempt() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("잠긴 메모: \(title)")
    }

    private func attempt() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        didFail = !(await onUnlock())
        isAuthenticating = false
    }
}
