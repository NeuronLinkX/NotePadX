import SwiftUI

/// 설정 > 보안. 잠근 메모를 얼마나 오래 열어 둘지, 바탕화면 위젯이 메모를 얼마나 보여줄지.
struct SecuritySettingsView: View {
    @ObservedObject private var session = NoteLockSession.shared
    @State private var widgetMode = WidgetSnapshotService.privacyMode

    var body: some View {
        Form {
            Section {
                Picker("열어 둔 잠긴 메모를 다시 잠글 때", selection: Binding(
                    get: { session.relockSeconds },
                    set: { session.relockSeconds = $0 }
                )) {
                    ForEach(NoteLockSession.relockChoices, id: \.seconds) { choice in
                        Text(choice.label).tag(choice.seconds)
                    }
                }
            } header: {
                Text("메모 잠금")
            } footer: {
                Text("메모를 우클릭해 '잠그기'를 고르면, 열 때마다 Touch ID(또는 Mac 암호)를 요구하고 목록 미리보기·검색 본문·위젯·연관 그래프·클라우드 동기화에서 내용을 숨깁니다. 이것은 화면 보호 기능이며 파일 암호화는 아닙니다 — 이 Mac의 디스크를 직접 열어 보는 사람까지 막지는 못합니다.")
            }

            Section {
                Picker("위젯에 표시할 내용", selection: $widgetMode) {
                    ForEach(WidgetPrivacyMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .onChange(of: widgetMode) { _, newValue in
                    WidgetSnapshotService.privacyMode = newValue
                    Task { await WidgetSnapshotService.shared.refresh() }
                }
            } header: {
                Text("바탕화면 위젯")
            } footer: {
                Text("위젯은 화면을 잠가 둔 동안에도 보일 수 있습니다. 잠긴 메모는 이 설정과 상관없이 위젯에 '잠긴 메모'로만 나옵니다.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 400)
    }
}
