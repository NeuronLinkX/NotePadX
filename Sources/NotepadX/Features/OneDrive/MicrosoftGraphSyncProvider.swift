import AppKit
import AuthenticationServices
import Foundation

/// 스펙 13.2절 선택 구현. OAuth 2.0 Authorization Code Flow with PKCE로 로그인하고,
/// OneDrive 앱 폴더(Files.ReadWrite.AppFolder)에만 접근한다. 비밀번호는 절대 이 앱을
/// 거치지 않는다 — 로그인은 시스템이 제공하는 ASWebAuthenticationSession 안에서 이뤄진다.
///
/// **참고**: 이 구현은 Microsoft 문서화된 OAuth2/Graph 계약대로 작성했지만, 실제 Azure AD
/// 테넌트/앱 등록(Client ID)이 없는 이 개발 환경에서는 로그인 화면까지 띄우는 실제 왕복
/// 테스트를 하지 못했다. `MicrosoftGraphConfig.clientID`가 nil이면(기본값) 이 provider는
/// 아예 쓰이지 않고, OneDrive 폴더 동기화(OneDriveFolderSyncProvider)만 동작한다.
@MainActor
final class MicrosoftGraphSyncProvider: NSObject, CloudSyncProvider, @unchecked Sendable {
    private let keychain: KeychainService
    private static let tokenKey = "microsoftGraphTokens"
    private var activeSession: ASWebAuthenticationSession?

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    // MARK: - 인증

    func authenticate() async throws {
        guard let clientID = MicrosoftGraphConfig.clientID else {
            throw AppError.authenticationRequired
        }
        let verifier = PKCEGenerator.generateCodeVerifier()
        let challenge = PKCEGenerator.codeChallenge(for: verifier)
        let state = PKCEGenerator.generateState()

        guard var components = URLComponents(url: MicrosoftGraphConfig.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw AppError.authenticationRequired
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: MicrosoftGraphConfig.redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: MicrosoftGraphConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authURL = components.url, let scheme = URL(string: MicrosoftGraphConfig.redirectURI)?.scheme else {
            throw AppError.authenticationRequired
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? AppError.authenticationRequired)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }
        activeSession = nil

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state,
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AppError.authenticationRequired
        }

        try await exchangeCodeForTokens(code: code, verifier: verifier, clientID: clientID)
    }

    func signOut() async throws {
        try keychain.removeValue(forKey: Self.tokenKey)
    }

    // MARK: - CloudSyncProvider (Graph 앱 폴더의 <uuid>.json 파일로 매핑)

    func listNotes() async throws -> [RemoteNote] {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(MicrosoftGraphConfig.graphAppFolderBase)/children?$select=name,lastModifiedDateTime")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)

        let list = try JSONDecoder().decode(DriveItemListResponse.self, from: data)
        return list.value.compactMap { item in
            guard item.name.hasSuffix(".json") else { return nil }
            let id = String(item.name.dropLast(5))
            // contentHash는 목록 조회만으로는 얻기 비싸서(각 파일을 다 받아야 함) 비워둔다 —
            // 우리 동기화 알고리즘은 listNotes()가 아니라 download(id:)로 직접 비교하므로 영향 없다.
            return RemoteNote(id: id, title: id, updatedAt: item.lastModifiedDateTime, contentHash: "")
        }
    }

    func upload(_ note: SyncDocument) async throws {
        let token = try await validAccessToken()
        let payload = try JSONEncoder.graphSync.encode(GraphNotePayload(from: note))

        var request = URLRequest(url: URL(string: "\(MicrosoftGraphConfig.graphAppFolderBase):/\(note.noteID.uuidString).json:/content")!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
    }

    func download(id: String) async throws -> SyncDocument {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(MicrosoftGraphConfig.graphAppFolderBase):/\(id).json:/content")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)

        let payload = try JSONDecoder.graphSync.decode(GraphNotePayload.self, from: data)
        return payload.toSyncDocument()
    }

    func delete(id: String) async throws {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(MicrosoftGraphConfig.graphAppFolderBase):/\(id).json")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
    }

    // MARK: - 토큰 교환/갱신/저장

    private func exchangeCodeForTokens(code: String, verifier: String, clientID: String) async throws {
        var request = URLRequest(url: MicrosoftGraphConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = Self.formEncode([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": MicrosoftGraphConfig.redirectURI,
            "code_verifier": verifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        try storeTokens(OAuthTokenSet(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        ))
    }

    private func validAccessToken() async throws -> String {
        guard let tokens = try loadTokens() else { throw AppError.authenticationRequired }
        if tokens.expiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }
        guard let refreshToken = tokens.refreshToken, let clientID = MicrosoftGraphConfig.clientID else {
            throw AppError.authenticationRequired
        }

        var request = URLRequest(url: MicrosoftGraphConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = Self.formEncode([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "redirect_uri": MicrosoftGraphConfig.redirectURI,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newTokens = OAuthTokenSet(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
        try storeTokens(newTokens)
        return newTokens.accessToken
    }

    private func storeTokens(_ tokens: OAuthTokenSet) throws {
        let data = try JSONEncoder.graphSync.encode(tokens)
        try keychain.setData(data, forKey: Self.tokenKey)
    }

    private func loadTokens() throws -> OAuthTokenSet? {
        guard let data = try keychain.data(forKey: Self.tokenKey) else { return nil }
        return try JSONDecoder.graphSync.decode(OAuthTokenSet.self, from: data)
    }

    private static func formEncode(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        let pairs = params.map { key, value -> String in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encodedValue)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError.cloudUnavailable }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw AppError.authenticationRequired
        case 403:
            throw AppError.permissionDenied
        case 404:
            throw SyncProviderError.notFound
        case 409:
            throw AppError.syncConflict
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw AppError.apiRateLimited(retryAfter: retryAfter)
        case 500...599:
            throw AppError.cloudUnavailable
        default:
            throw AppError.cloudUnavailable
        }
    }
}

extension MicrosoftGraphSyncProvider: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}

private struct OAuthTokenSet: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct DriveItemListResponse: Decodable {
    struct Item: Decodable {
        let name: String
        let lastModifiedDateTime: Date
    }
    let value: [Item]
}

/// Graph 앱 폴더에 저장하는 노트 JSON 파일의 내용. document.json/metadata.json으로 나누는
/// Finder 폴더 방식과 달리, Graph는 파일 하나짜리 업로드가 더 간단해서 한 파일에 합쳐 담는다.
private struct GraphNotePayload: Codable {
    var noteID: UUID
    var title: String
    var documentJSON: Data
    var plainText: String
    var updatedAt: Date
    var contentHash: String
    var deviceID: String

    init(from document: SyncDocument) {
        noteID = document.noteID
        title = document.title
        documentJSON = document.documentJSON
        plainText = document.plainText
        updatedAt = document.updatedAt
        contentHash = document.contentHash
        deviceID = document.deviceID
    }

    func toSyncDocument() -> SyncDocument {
        SyncDocument(
            noteID: noteID, title: title, documentJSON: documentJSON, plainText: plainText,
            updatedAt: updatedAt, contentHash: contentHash, baseRevision: nil, deviceID: deviceID
        )
    }
}

private extension JSONEncoder {
    static let graphSync: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let graphSync: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
