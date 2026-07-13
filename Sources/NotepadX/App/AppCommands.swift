import SwiftUI

// FocusedValue를 통해 현재 활성 화면(ContentView)이 제공하는 액션을
// 메뉴/단축키(AppCommands)와 연결한다. Commands는 씬 레벨에서 선언되므로
// 뷰 트리 안의 상태에 직접 접근할 수 없어 이 방식을 사용한다.

private struct NewNoteActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct NewFolderActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct SaveActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct ExportActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct ToggleHorizontalSplitActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct ToggleVerticalSplitActionKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var newNoteAction: (() -> Void)? {
        get { self[NewNoteActionKey.self] }
        set { self[NewNoteActionKey.self] = newValue }
    }
    var newFolderAction: (() -> Void)? {
        get { self[NewFolderActionKey.self] }
        set { self[NewFolderActionKey.self] = newValue }
    }
    var saveAction: (() -> Void)? {
        get { self[SaveActionKey.self] }
        set { self[SaveActionKey.self] = newValue }
    }
    var exportAction: (() -> Void)? {
        get { self[ExportActionKey.self] }
        set { self[ExportActionKey.self] = newValue }
    }
    var toggleHorizontalSplitAction: (() -> Void)? {
        get { self[ToggleHorizontalSplitActionKey.self] }
        set { self[ToggleHorizontalSplitActionKey.self] = newValue }
    }
    var toggleVerticalSplitAction: (() -> Void)? {
        get { self[ToggleVerticalSplitActionKey.self] }
        set { self[ToggleVerticalSplitActionKey.self] = newValue }
    }
}

/// 스펙 19절 File/View 메뉴. Format 메뉴는 서식 툴바(EditorToolbar)로 대체했고,
/// LLM 패널이 없는 지금은 View 메뉴에서 "Toggle AI Panel"은 뺐다.
struct AppCommands: Commands {
    @FocusedValue(\.newNoteAction) private var newNoteAction
    @FocusedValue(\.newFolderAction) private var newFolderAction
    @FocusedValue(\.saveAction) private var saveAction
    @FocusedValue(\.exportAction) private var exportAction
    @FocusedValue(\.toggleHorizontalSplitAction) private var toggleHorizontalSplitAction
    @FocusedValue(\.toggleVerticalSplitAction) private var toggleVerticalSplitAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { newNoteAction?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newNoteAction == nil)

            Button("New Folder") { newFolderAction?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(newFolderAction == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Save") { saveAction?() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(saveAction == nil)

            Button("Export…") { exportAction?() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exportAction == nil)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Horizontal Split") { toggleHorizontalSplitAction?() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(toggleHorizontalSplitAction == nil)
            Button("Vertical Split") { toggleVerticalSplitAction?() }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(toggleVerticalSplitAction == nil)
        }
    }
}
