import AppKit

/// 스펙 10절: "앱이 비활성화될 때 즉시 저장", "앱 종료 시 저장 완료를 보장"을 구현한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillResignActive(_ notification: Notification) {
        Task { @MainActor in
            await SaveCoordinator.shared.flushAll()
        }
    }

    /// 대기 중인 자동 저장을 모두 완료할 때까지 종료를 미룬 뒤 실제로 종료한다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await SaveCoordinator.shared.flushAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
