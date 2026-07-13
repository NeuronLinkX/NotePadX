import Foundation

/// 스펙 16절 기본 기능 목록. `.custom`은 사용자가 직접 프롬프트를 입력하는 경우다.
enum AITaskType: String, CaseIterable, Identifiable, Sendable {
    case summarize
    case polish
    case spellCheck
    case formalTone
    case concise
    case expand
    case translate
    case generateTitle
    case generateTOC
    case continueWriting
    case extractKeyPoints
    case convertToTable
    case explainSelection
    case explainCppCode
    case explainRustCode
    case findCodeErrors
    case refactorCode
    case generateComments
    case convertCppToRust
    case convertRustToCpp
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .summarize: return "요약"
        case .polish: return "문장 다듬기"
        case .spellCheck: return "맞춤법 교정"
        case .formalTone: return "전문적인 문체로 변경"
        case .concise: return "간결하게 변경"
        case .expand: return "자세하게 확장"
        case .translate: return "번역"
        case .generateTitle: return "제목 생성"
        case .generateTOC: return "목차 생성"
        case .continueWriting: return "이어 쓰기"
        case .extractKeyPoints: return "핵심 항목 추출"
        case .convertToTable: return "표로 정리"
        case .explainSelection: return "선택 문장 설명"
        case .explainCppCode: return "C++ 코드 설명"
        case .explainRustCode: return "Rust 코드 설명"
        case .findCodeErrors: return "코드 오류 찾기"
        case .refactorCode: return "코드 리팩터링"
        case .generateComments: return "주석 생성"
        case .convertCppToRust: return "C++ → Rust 변환"
        case .convertRustToCpp: return "Rust → C++ 변환"
        case .custom: return "사용자 정의 프롬프트"
        }
    }

    /// 사용자 명령(user role) 프롬프트에 들어갈 지시문. 실제 선택 본문/문서는
    /// PromptBuilder가 별도 역할로 분리해서 붙인다 — 여기 텍스트에는 문서 내용을 섞지 않는다.
    var instruction: String {
        switch self {
        case .summarize: return "다음 텍스트를 핵심만 남겨 간결하게 요약하라."
        case .polish: return "다음 텍스트의 문장을 자연스럽게 다듬어라. 의미는 바꾸지 마라."
        case .spellCheck: return "다음 텍스트의 맞춤법과 띄어쓰기를 교정하라. 교정된 전체 텍스트만 출력하라."
        case .formalTone: return "다음 텍스트를 전문적이고 격식 있는 문체로 바꿔라."
        case .concise: return "다음 텍스트를 더 간결하게 줄여라. 핵심 의미는 유지하라."
        case .expand: return "다음 텍스트를 더 자세하고 풍부하게 확장하라."
        case .translate: return "다음 텍스트를 자연스러운 영어로 번역하라. 원문 언어가 영어면 한국어로 번역하라."
        case .generateTitle: return "다음 텍스트의 내용을 대표하는 짧은 제목을 하나만 제안하라."
        case .generateTOC: return "다음 텍스트의 구조를 바탕으로 목차(마크다운 목록)를 만들어라."
        case .continueWriting: return "다음 텍스트의 흐름과 문체를 이어서 자연스럽게 계속 작성하라."
        case .extractKeyPoints: return "다음 텍스트에서 핵심 항목을 글머리 기호 목록으로 추출하라."
        case .convertToTable: return "다음 텍스트의 정보를 마크다운 표로 정리하라."
        case .explainSelection: return "다음 문장이 의미하는 바를 쉽게 설명하라."
        case .explainCppCode: return "다음 C++ 코드가 하는 일을 한국어로 설명하라."
        case .explainRustCode: return "다음 Rust 코드가 하는 일을 한국어로 설명하라."
        case .findCodeErrors: return "다음 코드에서 버그나 잠재적 오류를 찾아 나열하라."
        case .refactorCode: return "다음 코드를 가독성과 성능 측면에서 리팩터링하라. 코드만 출력하라."
        case .generateComments: return "다음 코드에 설명 주석을 추가하라. 코드 전체를 주석과 함께 출력하라."
        case .convertCppToRust: return "다음 C++ 코드를 동등한 Rust 코드로 변환하라. 코드만 출력하라."
        case .convertRustToCpp: return "다음 Rust 코드를 동등한 C++ 코드로 변환하라. 코드만 출력하라."
        case .custom: return ""
        }
    }

    /// 코드 관련 작업은 기본적으로 선택된 코드 블록만 보내는 게 자연스럽다.
    var defaultScope: AIContextScope {
        switch self {
        case .explainCppCode, .explainRustCode, .findCodeErrors, .refactorCode,
             .generateComments, .convertCppToRust, .convertRustToCpp:
            return .codeBlockOnly
        case .generateTitle, .generateTOC, .continueWriting:
            return .fullDocument
        default:
            return .selectionOnly
        }
    }
}

/// 전송 전 사용자에게 무엇을 보내는지 보여주기 위한 범위 선택 (스펙 16절).
enum AIContextScope: String, CaseIterable, Identifiable, Sendable {
    case selectionOnly
    case fullDocument
    case codeBlockOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selectionOnly: return "선택 영역만"
        case .fullDocument: return "전체 문서"
        case .codeBlockOnly: return "코드 블록만"
        }
    }
}

/// LLM 응답을 문서에 반영하는 방식.
enum AIApplyAction: String, CaseIterable, Identifiable, Sendable {
    case replaceSelection
    case insertBelowSelection
    case insertAtEnd
    case newNote
    case panelOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .replaceSelection: return "선택 영역 교체"
        case .insertBelowSelection: return "선택 영역 아래 삽입"
        case .insertAtEnd: return "문서 끝에 삽입"
        case .newNote: return "새 메모로 생성"
        case .panelOnly: return "패널에만 표시"
        }
    }

    /// 문서 전체를 사실상 바꿔버리는 적용 방식은 되돌리기용 리비전을 먼저 남겨야 한다.
    var requiresRevisionBeforeApply: Bool {
        self == .replaceSelection || self == .insertBelowSelection || self == .insertAtEnd
    }
}
