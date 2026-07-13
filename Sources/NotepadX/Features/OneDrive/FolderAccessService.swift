import AppKit
import Foundation

/// 사용자가 Finder에서 고른 OneDrive(또는 그 하위) 폴더에 대한 App Sandbox
/// security-scoped bookmark를 만들고, Keychain에 저장했다가 다음 실행 때 복원한다 (스펙 13.1절).
@MainActor
final class FolderAccessService: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var needsReselection = false

    private let keychain: KeychainService
    private static let bookmarkKey = "oneDriveFolderBookmark"

    private var isAccessingSecurityScopedResource = false

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    /// 앱 시작 시 한 번 호출해 이전에 골라둔 폴더 접근 권한을 복원한다.
    func restoreAccessIfAvailable() {
        do {
            guard let bookmarkData = try keychain.data(forKey: Self.bookmarkKey) else { return }
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                needsReselection = true
                return
            }
            isAccessingSecurityScopedResource = true
            folderURL = url

            if isStale {
                // 북마크는 유효하지만 오래됐다 — 새 북마크로 갱신해 다음 실행에도 문제없게 한다.
                try? persistBookmark(for: url)
            }
        } catch {
            needsReselection = true
        }
    }

    /// NSOpenPanel로 폴더를 고르게 하고, 고른 폴더의 북마크를 Keychain에 저장한다.
    @discardableResult
    func presentFolderPicker() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "OneDrive 동기화에 사용할 폴더를 선택하세요."
        panel.prompt = "선택"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        stopAccessing()
        do {
            try persistBookmark(for: url)
            guard url.startAccessingSecurityScopedResource() else {
                needsReselection = true
                return nil
            }
            isAccessingSecurityScopedResource = true
            folderURL = url
            needsReselection = false
            return url
        } catch {
            needsReselection = true
            return nil
        }
    }

    func forgetFolder() {
        stopAccessing()
        folderURL = nil
        needsReselection = false
        try? keychain.removeValue(forKey: Self.bookmarkKey)
    }

    private func persistBookmark(for url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try keychain.setData(bookmarkData, forKey: Self.bookmarkKey)
    }

    private func stopAccessing() {
        if isAccessingSecurityScopedResource {
            folderURL?.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
        }
    }

    // 이 서비스는 AppEnvironment가 앱 생명주기 동안 계속 들고 있어 deinit이 사실상 호출되지
    // 않는다. 설령 호출되더라도 보안 스코프 리소스 접근은 프로세스 종료 시 OS가 정리하므로
    // (deinit은 격리되지 않은 컨텍스트라 MainActor 프로퍼티를 여기서 안전하게 읽을 방법이
    // 마땅치 않다) 별도 정리를 하지 않는다.
}
