import Foundation

/// SPM(`swift build`/`swift run`)과 XcodeGen이 만든 `.app` 번들 양쪽에서
/// 동일한 `Resources/WebEditor` 폴더 구조를 찾기 위한 얇은 추상화.
/// SPM 빌드에서는 `Bundle.module`(SWIFT_PACKAGE 매크로로만 존재)을,
/// 일반 Xcode 앱 타깃에서는 `Bundle.main`을 사용한다.
enum WebEditorResources {
    static var resourceRootURL: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.resourceURL
        #else
        return Bundle.main.resourceURL
        #endif
    }

    static var indexHTMLURL: URL? {
        resourceRootURL?
            .appendingPathComponent("WebEditor", isDirectory: true)
            .appendingPathComponent("index.html", isDirectory: false)
    }

    static var webEditorDirectoryURL: URL? {
        resourceRootURL?.appendingPathComponent("WebEditor", isDirectory: true)
    }
}
