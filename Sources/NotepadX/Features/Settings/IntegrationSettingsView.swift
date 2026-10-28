import SwiftUI

/// 설정 > 연동. 빠른 메모(전역 단축키·메뉴 막대), Spotlight 검색, 단축어.
struct IntegrationSettingsView: View {
    @AppStorage(QuickCaptureController.hotKeyEnabledKey, store: AppConfig.defaults) private var hotKeyEnabled = true
    @AppStorage(QuickCaptureController.menuBarEnabledKey, store: AppConfig.defaults) private var menuBarEnabled = false
    @AppStorage(SpotlightIndexService.enabledKey, store: AppConfig.defaults) private var spotlightEnabled = true
    @AppStorage(SpotlightIndexService.previewsKey, store: AppConfig.defaults) private var spotlightPreviews = true

    var body: some View {
        Form {
            Section {
                Toggle("전역 단축키 ⌃⌥N 으로 빠른 메모 열기", isOn: $hotKeyEnabled)
                    .onChange(of: hotKeyEnabled) { _, _ in
                        QuickCaptureController.shared.applyHotKeySetting()
                    }
                Toggle("메뉴 막대에 아이콘 표시", isOn: $menuBarEnabled)
            } header: {
                Text("빠른 메모")
            } footer: {
                Text("앱이 다른 창 뒤에 있어도 단축키로 작은 입력창을 띄워 바로 적을 수 있습니다. 첫 줄이 제목이 되고 ⌘↩로 저장합니다. 파일 메뉴의 '빠른 메모…'로도 열 수 있습니다.")
            }

            Section {
                Toggle("Spotlight 검색에 메모 포함", isOn: $spotlightEnabled)
                    .onChange(of: spotlightEnabled) { _, _ in
                        Task { await ExternalSurfaces.refresh() }
                    }
                Toggle("미리보기도 함께 표시 (끄면 제목만)", isOn: $spotlightPreviews)
                    .disabled(!spotlightEnabled)
                    .onChange(of: spotlightPreviews) { _, _ in
                        Task { await ExternalSurfaces.refresh() }
                    }
            } header: {
                Text("Spotlight")
            } footer: {
                Text("켜면 Spotlight(⌘Space)에서 메모를 찾아 바로 열 수 있습니다. 잠긴 메모와 휴지통의 메모는 포함하지 않습니다. 끄면 이미 등록된 항목도 지웁니다.")
            }

            Section {
                Label("단축어 앱에서 'Notepad' 동작을 찾아 새 메모 만들기 / 텍스트로 메모 만들기를 자동화에 쓸 수 있습니다.", systemImage: "wand.and.stars")
                    .font(.callout)
            } header: {
                Text("단축어")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
    }
}
