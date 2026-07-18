import AppKit

/// 스펙 10절: "앱이 비활성화될 때 즉시 저장", "앱 종료 시 저장 완료를 보장"을 구현한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// macOS가 Edit 메뉴에 자동으로 넣어주는 "받아쓰기 시작" 항목은 시스템 받아쓰기 언어에
    /// 따라 동작하는데, 사용자 환경에서 한국어는 지원되지 않고 영어만 동작해 쓸모가 없다.
    /// 메뉴가 만들어지기 전(앱 launch 완료 전)에 이 UserDefaults 키를 켜두면 AppKit이 그
    /// 항목 자체를 Edit 메뉴에 추가하지 않는다.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
    }

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
