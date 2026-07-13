import Foundation

/// 앱 전역에서 사용자에게 보여줄 수 있는 오류. 기술적인 stack trace 대신
/// "무엇이 실패했는지 / 데이터가 보존되었는지 / 무엇을 할 수 있는지"를 담는다.
enum AppError: LocalizedError, Sendable, Equatable {
    case databaseFailure(String)
    case documentCorrupted
    case saveFailed(path: String?)
    case permissionDenied
    case securityBookmarkExpired
    case cloudUnavailable
    case syncConflict
    case authenticationRequired
    case apiRateLimited(retryAfter: TimeInterval?)
    case exportFailed(format: String)

    var errorDescription: String? {
        switch self {
        case .databaseFailure(let reason):
            return "데이터베이스 작업에 실패했습니다 (\(reason)). 데이터는 마지막 저장 시점까지 보존됩니다."
        case .documentCorrupted:
            return "문서 데이터를 읽을 수 없습니다. 최근 버전 기록에서 복원을 시도해 보세요."
        case .saveFailed(let path):
            return "저장에 실패했습니다\(path.map { " (\($0))" } ?? ""). 변경 내용은 편집기에 남아 있으니 다시 저장해 보세요."
        case .permissionDenied:
            return "이 위치에 접근할 권한이 없습니다. 설정에서 폴더 접근 권한을 다시 부여해 주세요."
        case .securityBookmarkExpired:
            return "저장된 폴더 접근 권한이 만료되었습니다. 폴더를 다시 선택해 주세요."
        case .cloudUnavailable:
            return "지금은 클라우드 저장소에 연결할 수 없습니다. 변경 내용은 로컬에 저장되며 연결이 복구되면 동기화됩니다."
        case .syncConflict:
            return "같은 노트가 로컬과 클라우드에서 모두 수정되었습니다. 어떤 버전을 유지할지 선택해 주세요."
        case .authenticationRequired:
            return "다시 로그인해야 합니다."
        case .apiRateLimited(let retryAfter):
            if let retryAfter {
                return "요청이 너무 많습니다. \(Int(retryAfter))초 후 다시 시도해 주세요."
            }
            return "요청이 너무 많습니다. 잠시 후 다시 시도해 주세요."
        case .exportFailed(let format):
            return "\(format) 형식으로 내보내지 못했습니다. 원본 노트는 변경되지 않았습니다."
        }
    }

    var isDataPreserved: Bool {
        switch self {
        case .documentCorrupted: return false
        default: return true
        }
    }
}
