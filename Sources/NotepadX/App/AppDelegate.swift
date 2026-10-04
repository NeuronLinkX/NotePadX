import AppKit

/// 스펙 10절: "앱이 비활성화될 때 즉시 저장", "앱 종료 시 저장 완료를 보장"을 구현한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// macOS가 Edit 메뉴에 자동으로 넣어주는 "받아쓰기 시작" 항목은 시스템 받아쓰기 언어에
    /// 따라 동작하는데, 사용자 환경에서 한국어는 지원되지 않고 영어만 동작해 쓸모가 없다.
    /// 메뉴가 만들어지기 전(앱 launch 완료 전)에 이 UserDefaults 키를 켜두면 AppKit이 그
    /// 항목 자체를 Edit 메뉴에 추가하지 않는다.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")

        // 위젯의 notepadx:// 링크를 SwiftUI보다 먼저 직접 받는다. SwiftUI(WindowGroup)에 맡기면
        // 링크마다 새 창이 만들어지고 handlesExternalEvents로도 막히지 않는다.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw),
              let link = WidgetDeepLink(url: url) else { return }
        Task { @MainActor in
            WidgetDeepLinkRouter.shared.pending = link
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }

    /// 사용자가 다른 앱/바탕화면으로 넘어가는 순간이 위젯을 보게 되는 순간이므로, 저장을
    /// 마친 직후 위젯용 최근 메모 요약도 같이 갱신한다.
    func applicationWillResignActive(_ notification: Notification) {
        Task { @MainActor in
            await SaveCoordinator.shared.flushAll()
            await WidgetSnapshotService.shared.refresh()
        }
    }

    /// 대기 중인 자동 저장을 모두 완료할 때까지 종료를 미룬 뒤 실제로 종료한다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await SaveCoordinator.shared.flushAll()
            await WidgetSnapshotService.shared.refresh()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
