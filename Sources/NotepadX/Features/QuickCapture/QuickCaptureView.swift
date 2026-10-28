import SwiftUI

/// 어디서든 단축키로 띄우는 작은 입력창의 내용. 첫 줄이 제목이 되고, ⌘↩로 저장, Esc로 닫는다.
struct QuickCaptureView: View {
    let onSave: (String) async -> Bool
    let onCancel: () -> Void

    @State private var text = ""
    @State private var isSaving = false
    @State private var errorText: String?
    @FocusState private var isFocused: Bool

    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").foregroundStyle(.secondary)
                Text("빠른 메모").font(.headline)
                Spacer()
                Text("첫 줄이 제목이 됩니다").font(.caption).foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .font(.body)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                .frame(minHeight: 150)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Text("⌘↩ 저장 · Esc 닫기").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    Text("저장")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onAppear { isFocused = true }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorText = nil
        let ok = await onSave(text)
        isSaving = false
        if ok {
            text = ""
        } else {
            errorText = "저장하지 못했습니다. 잠시 후 다시 시도해 주세요."
        }
    }
}
