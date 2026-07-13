import SwiftUI

/// File > Export… 로 여는 내보내기 시트 (스펙 15절). 형식을 고르고 옵션을 설정한 뒤
/// 저장하면, 완료 화면에서 Finder에 표시/기본 앱으로 열기/공유/이메일 첨부로 이어간다.
struct ExportView: View {
    @ObservedObject var viewModel: ExportViewModel
    let note: Note
    let title: String
    let document: EditorDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Form {
                Section("형식") {
                    Picker("형식", selection: $viewModel.format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if showsDocumentOptions {
                    Section("포함 항목") {
                        Toggle("제목 포함", isOn: $viewModel.options.includeTitle)
                        Toggle("생성일·수정일 포함", isOn: $viewModel.options.includeDates)
                        Toggle("코드 블록 줄 번호", isOn: $viewModel.options.codeBlockLineNumbers)
                        TextField("작성자 (선택)", text: $viewModel.options.author)
                    }
                }

                if showsPageOptions {
                    Section("페이지") {
                        Picker("테마", selection: $viewModel.options.theme) {
                            ForEach(ExportTheme.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("용지 크기", selection: $viewModel.options.pageSize) {
                            ForEach(ExportPageSize.allCases) { Text($0.displayName).tag($0) }
                        }
                        Picker("여백", selection: $viewModel.options.margins) {
                            ForEach(ExportMargins.allCases) { Text($0.displayName).tag($0) }
                        }
                        Toggle("머리글/바닥글 포함", isOn: $viewModel.options.includeHeaderFooter)
                    }
                }

                if showsCodeFontOption {
                    Section("코드") {
                        TextField("코드 글꼴", text: $viewModel.options.codeFont)
                    }
                }

                if viewModel.format == .docx {
                    Section("표") {
                        Toggle("표 테두리 표시", isOn: $viewModel.options.showTableBorders)
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            footer
        }
        .frame(width: 460, height: 520)
    }

    private var header: some View {
        HStack {
            Text("내보내기").font(.title2.bold())
            Spacer()
            Button("닫기") { dismiss() }
        }
        .padding()
    }

    @ViewBuilder
    private var footer: some View {
        if let exportedURL = viewModel.lastExportedURL {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(exportedURL.lastPathComponent) 로 내보냈습니다.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                HStack {
                    Button("Finder에 표시") { viewModel.revealInFinder() }
                    Button("기본 앱으로 열기") { viewModel.openInDefaultApp() }
                    ShareButton(url: exportedURL).frame(width: 90)
                    Button("이메일 첨부") { viewModel.attachToEmail() }
                }
            }
            .padding()
        } else {
            HStack {
                Spacer()
                if viewModel.isExporting {
                    ProgressView().controlSize(.small)
                    Text("내보내는 중…").foregroundStyle(.secondary)
                }
                Button("내보내기") {
                    Task { await viewModel.exportAndSave(note: note, title: title, document: document) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isExporting)
            }
            .padding()
        }
    }

    private var showsDocumentOptions: Bool {
        viewModel.format != .json
    }

    private var showsPageOptions: Bool {
        [.html, .pdf, .rtf, .rtfd].contains(viewModel.format)
    }

    private var showsCodeFontOption: Bool {
        [.html, .pdf, .rtf, .rtfd, .docx].contains(viewModel.format)
    }
}
