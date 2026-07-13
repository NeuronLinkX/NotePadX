import Foundation

/// Info.plist의 MicrosoftEntraClientID/MicrosoftEntraRedirectURI는 project.yml의
/// MICROSOFT_ENTRA_CLIENT_ID 빌드 설정에서 채워진다. 값이 없으면(빈 문자열) clientID가 nil이
/// 되고, 앱은 Microsoft Graph 로그인 버튼을 비활성화한 채로 로컬 기능만 정상 제공해야 한다.
enum MicrosoftGraphConfig {
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MicrosoftEntraClientID") as? String,
              !value.isEmpty else { return nil }
        return value
    }

    static var redirectURI: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MicrosoftEntraRedirectURI") as? String, !value.isEmpty {
            return value
        }
        return "msauth.\(AppConfig.bundleIdentifier)://auth"
    }

    /// 최소 권한만 요청한다 (스펙 13.2절: 가능하면 Files.ReadWrite.AppFolder).
    static let scopes = ["Files.ReadWrite.AppFolder", "offline_access"]

    static let authorizationEndpoint = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
    static let tokenEndpoint = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!
    /// 앱 전용 폴더(OneDrive의 "Apps/NotepadX")만 접근한다.
    static let graphAppFolderBase = "https://graph.microsoft.com/v1.0/me/drive/special/approot"
}
