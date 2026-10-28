import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 빠른 메모 창과 전역 단축키(⌃⌥N). 앱이 다른 창 뒤에 있거나 창이 하나도 없어도 떠오른다.
/// 단축키는 Carbon의 RegisterEventHotKey를 쓴다 — 손쉬운 사용 권한 없이 샌드박스 안에서 동작한다.
@MainActor
final class QuickCaptureController: NSObject {
    static let shared = QuickCaptureController()

    static let hotKeyEnabledKey = "NotepadX.quickCapture.hotKeyEnabled"
    static let menuBarEnabledKey = "NotepadX.quickCapture.menuBarEnabled"

    private var service: QuickCaptureService?
    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var isReady: Bool { service != nil }

    static var isHotKeyEnabled: Bool {
        get { AppConfig.defaults.object(forKey: hotKeyEnabledKey) as? Bool ?? true }
        set { AppConfig.defaults.set(newValue, forKey: hotKeyEnabledKey) }
    }

    func configure(noteUseCase: NoteUseCase) {
        service = QuickCaptureService(noteUseCase: noteUseCase)
        applyHotKeySetting()
    }

    // MARK: - 단축키

    func applyHotKeySetting() {
        if Self.isHotKeyEnabled { registerHotKey() } else { unregisterHotKey() }
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { QuickCaptureController.shared.toggle() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        guard status == noErr else { return }
        let id = EventHotKeyID(signature: OSType(0x4E50_4458), id: 1)   // 'NPDX'
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    // MARK: - 창

    func toggle() {
        if let panel, panel.isVisible { hide() } else { show() }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: QuickCaptureView(
            onSave: { [weak self] text in
                guard let self else { return false }
                let saved = await self.save(text)
                if saved { self.hide() }
                return saved
            },
            onCancel: { [weak self] in self?.hide() }
        ))
        return panel
    }

    // MARK: - 저장

    func save(_ text: String) async -> Bool {
        guard let service else { return false }
        return ((try? await service.save(text: text)) ?? nil) != nil
    }

    /// 단축어(App Intents)처럼 앱이 막 켜지는 중에 호출될 수 있어서, 준비될 때까지 잠깐 기다린다.
    func saveWhenReady(_ text: String, timeout: TimeInterval = 15) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isReady, Date() < deadline { try? await Task.sleep(nanoseconds: 200_000_000) }
        return await save(text)
    }
}
