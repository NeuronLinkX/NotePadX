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
private struct FindActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct ReplaceActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct GoToLineActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct NewTabActionKey: FocusedValueKey { typealias Value = () -> Void }
private struct CloseTabActionKey: FocusedValueKey { typealias Value = () -> Void }

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
    var findAction: (() -> Void)? {
        get { self[FindActionKey.self] }
        set { self[FindActionKey.self] = newValue }
    }
    var replaceAction: (() -> Void)? {
        get { self[ReplaceActionKey.self] }
        set { self[ReplaceActionKey.self] = newValue }
    }
    var goToLineAction: (() -> Void)? {
        get { self[GoToLineActionKey.self] }
        set { self[GoToLineActionKey.self] = newValue }
    }
    var newTabAction: (() -> Void)? {
        get { self[NewTabActionKey.self] }
        set { self[NewTabActionKey.self] = newValue }
    }
    var closeTabAction: (() -> Void)? {
        get { self[CloseTabActionKey.self] }
        set { self[CloseTabActionKey.self] = newValue }
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
    @FocusedValue(\.findAction) private var findAction
    @FocusedValue(\.replaceAction) private var replaceAction
    @FocusedValue(\.goToLineAction) private var goToLineAction
    @FocusedValue(\.newTabAction) private var newTabAction
    @FocusedValue(\.closeTabAction) private var closeTabAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { newNoteAction?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newNoteAction == nil)

            Button("New Folder") { newFolderAction?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(newFolderAction == nil)

            // 브라우저 스타일 탭 (스펙: 다중 탭 지원). Ctrl+T/Ctrl+W는 Windows 관례라
            // macOS 관례인 Cmd+T/Cmd+W로 바꿨다.
            Button("New Tab") { newTabAction?() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(newTabAction == nil)

            Button("Close Tab") { closeTabAction?() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(closeTabAction == nil)
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

        // 찾기/바꾸기/줄 이동. Windows 관례인 Ctrl+F·Ctrl+H·Ctrl+G 대신, macOS 텍스트
        // 편집기(Xcode 등)에서 흔히 쓰는 Cmd+F·Cmd+Option+F·Cmd+L로 맞췄다.
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { findAction?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(findAction == nil)
            Button("Find and Replace…") { replaceAction?() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(replaceAction == nil)
            Button("Go to Line…") { goToLineAction?() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(goToLineAction == nil)
        }
    }
}
