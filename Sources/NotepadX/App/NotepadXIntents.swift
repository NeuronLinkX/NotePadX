import AppIntents
import Foundation

/// 단축어 앱·Spotlight·Siri에서 쓸 수 있는 동작. 앱 프로세스 안에서 실행되므로, 데이터베이스가 준비되기
/// 전에 호출돼도(앱이 막 켜지는 중) 준비될 때까지 기다린다.
struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "새 메모 만들기"
    static let description = IntentDescription("Notepad에서 빈 새 메모를 엽니다.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetDeepLinkRouter.shared.pending = .newNote
        return .result()
    }
}

struct QuickNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "텍스트로 메모 만들기"
    static let description = IntentDescription("입력한 텍스트로 새 메모를 만듭니다. 첫 줄이 제목이 됩니다.")
    static let openAppWhenRun = true

    @Parameter(title: "내용", requestValueDialog: "메모에 적을 내용을 알려 주세요.")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let saved = await QuickCaptureController.shared.saveWhenReady(text)
        // 삼항 연산자의 결과는 문자열 리터럴이 아니므로 IntentDialog로 명시해서 넘긴다(CI의 Xcode에서 컴파일 오류).
        let message = saved ? "메모를 저장했어요." : "메모를 저장하지 못했어요. 내용이 비어 있거나 앱이 아직 준비되지 않았어요."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct NotepadXShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewNoteIntent(),
            phrases: ["\(.applicationName)에서 새 메모", "\(.applicationName) 새 메모 만들기"],
            shortTitle: "새 메모",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: QuickNoteIntent(),
            phrases: ["\(.applicationName)에 메모 남기기"],
            shortTitle: "텍스트로 메모",
            systemImageName: "text.badge.plus"
        )
    }
}
