import Foundation
import Security

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataCorrupted

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "알 수 없는 오류"
            return "Keychain 접근에 실패했습니다 (\(status)): \(message)"
        case .dataCorrupted:
            return "Keychain에 저장된 데이터를 읽을 수 없습니다."
        }
    }
}

/// API 키, OAuth 토큰, 보안 스코프 북마크처럼 민감한 데이터를 macOS Keychain에만 저장한다.
/// UserDefaults나 SQLite에는 절대 넣지 않는다 (스펙 16/22절).
struct KeychainService: Sendable {
    private let service: String

    init(service: String = AppConfig.bundleIdentifier) {
        self.service = service
    }

    func setData(_ data: Data, forKey key: String) throws {
        var query = baseQuery(forKey: key)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
        } else if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func data(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw KeychainError.dataCorrupted }
        return data
    }

    func setString(_ string: String, forKey key: String) throws {
        try setData(Data(string.utf8), forKey: key)
    }

    func string(forKey key: String) throws -> String? {
        guard let data = try data(forKey: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { throw KeychainError.dataCorrupted }
        return string
    }

    func removeValue(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
