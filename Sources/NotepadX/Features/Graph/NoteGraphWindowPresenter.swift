import AppKit
import SwiftUI

/// "연관 메모"를 좁은 사이드 패널 대신 독립된 macOS 창으로 연다(스펙: 화면 전체를 볼 수
/// 있게 — 표준 창이라 사용자가 크기 조절·최대화까지 자유롭게 할 수 있다).
@MainActor
final class NoteGraphWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var viewModel: NoteGraphViewModel?

    func show(viewModel: NoteGraphViewModel) {
        self.viewModel = viewModel
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: NoteGraphFullView(viewModel: viewModel))
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "연관 메모"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 960, height: 720))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.viewModel?.markHidden()
        }
    }
}
