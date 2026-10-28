import Foundation
import LocalAuthentication

extension Notification.Name {
    /// 목록에서 메모를 잠그거나 풀었을 때, 이미 열려 있는 편집기가 바로 반영하도록 알린다.
    /// userInfo: ["id": UUID, "isLocked": Bool]
    static let noteLockChanged = Notification.Name("NotepadX.noteLockChanged")
}

protocol NoteAuthenticating: Sendable {
    func authenticate(reason: String) async -> Bool
}

/// Touch ID, 안 되면 Mac 로그인 암호. 사용자가 취소하거나 인증할 수단이 없으면 false.
struct SystemNoteAuthenticator: NoteAuthenticating {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "취소"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// 항상 통과/거부시키는 인증기. **격리 프로필(시연·시험)에서 `NOTEPADX_FAKE_AUTH=allow|deny`를 줬을 때만**
/// 쓴다 — 격리 프로필에는 실제 메모가 없으므로, 사람이 지문을 대지 않아도 잠금 화면과 열린 상태를 자동으로
/// 점검할 수 있다.
struct AlwaysAllowAuthenticator: NoteAuthenticating {
    func authenticate(reason: String) async -> Bool { true }
}

struct AlwaysDenyAuthenticator: NoteAuthenticating {
    func authenticate(reason: String) async -> Bool { false }
}

/// 이번 실행 동안 "인증을 통과해 열어 둔" 메모를 기억하고, 앱을 떠나 있던 시간이 설정값을 넘으면
/// 다시 잠근다. 디스크에는 아무것도 남기지 않는다 — 앱을 껐다 켜면 모두 잠긴 상태로 시작한다.
@MainActor
final class NoteLockSession: ObservableObject {
    static let shared = NoteLockSession()

    /// 앱을 떠난 뒤 몇 초가 지나면 다시 잠글지. 0 = 떠나는 즉시, -1 = 앱을 끌 때까지 유지.
    static let relockChoices: [(seconds: Int, label: String)] = [
        (0, "앱을 떠나면 바로"), (60, "1분 뒤"), (300, "5분 뒤"), (-1, "앱을 끌 때까지 유지"),
    ]
    static let defaultRelockSeconds = 60
    private static let relockKey = "NotepadX.lock.relockSeconds"

    @Published private(set) var unlockedIDs: Set<UUID> = []

    private let authenticator: NoteAuthenticating
    private let defaults: UserDefaults
    private let now: () -> Date
    private var resignedAt: Date?

    init(
        authenticator: NoteAuthenticating = NoteLockSession.defaultAuthenticator(),
        defaults: UserDefaults = AppConfig.defaults,
        now: @escaping () -> Date = Date.init
    ) {
        self.authenticator = authenticator
        self.defaults = defaults
        self.now = now
    }

    nonisolated static func defaultAuthenticator() -> NoteAuthenticating {
        if AppConfig.isIsolatedProfile {
            switch ProcessInfo.processInfo.environment["NOTEPADX_FAKE_AUTH"] {
            case "allow": return AlwaysAllowAuthenticator()
            case "deny": return AlwaysDenyAuthenticator()
            default: break
            }
        }
        return SystemNoteAuthenticator()
    }

    var relockSeconds: Int {
        get { defaults.object(forKey: Self.relockKey) as? Int ?? Self.defaultRelockSeconds }
        set {
            defaults.set(newValue, forKey: Self.relockKey)
            objectWillChange.send()
        }
    }

    func isUnlocked(_ id: UUID) -> Bool { unlockedIDs.contains(id) }

    /// 인증만 한다(열어 둔 목록에는 넣지 않는다) — 잠금을 영구 해제하기 전 확인용.
    func authenticate(reason: String) async -> Bool {
        await authenticator.authenticate(reason: reason)
    }

    /// 인증에 성공하면 이번 실행 동안 이 메모를 열어 둔다.
    @discardableResult
    func unlock(_ id: UUID, reason: String) async -> Bool {
        guard await authenticator.authenticate(reason: reason) else { return false }
        unlockedIDs.insert(id)
        return true
    }

    func forget(_ id: UUID) {
        unlockedIDs.remove(id)
    }

    func lockAll() {
        unlockedIDs.removeAll()
    }

    func appDidResignActive() {
        resignedAt = now()
        if relockSeconds == 0 { lockAll() }
    }

    func appDidBecomeActive() {
        defer { resignedAt = nil }
        let limit = relockSeconds
        guard limit > 0, let resignedAt, now().timeIntervalSince(resignedAt) >= TimeInterval(limit) else { return }
        lockAll()
    }
}
