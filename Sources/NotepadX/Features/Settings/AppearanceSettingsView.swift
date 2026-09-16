import SwiftUI

/// 설정 > 모양 탭. 다크 모드(시스템 동기화/밝게/어둡게)와 색상 테마를 고른다.
struct AppearanceSettingsView: View {
    @ObservedObject var store: AppearanceSettingsStore

    var body: some View {
        Form {
            Section("모드") {
                Picker("모드", selection: $store.appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            Section("색상 테마") {
                ForEach(ColorTheme.allCases) { theme in
                    themeRow(theme)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 340)
    }

    private func themeRow(_ theme: ColorTheme) -> some View {
        Button {
            store.colorTheme = theme
        } label: {
            HStack {
                Text(theme.emoji).font(.title3)
                Circle().fill(theme.accentColor).frame(width: 14, height: 14)
                Text(theme.displayName)
                Spacer()
                if store.colorTheme == theme {
                    Image(systemName: "checkmark").foregroundStyle(theme.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
