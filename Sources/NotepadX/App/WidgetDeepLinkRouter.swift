import Foundation

/// 위젯에서 온 notepadx:// 링크(AppDelegate가 Apple Event로 직접 받음)를 화면(ContentView)으로 넘겨주는 통로.
@MainActor
final class WidgetDeepLinkRouter: ObservableObject {
    static let shared = WidgetDeepLinkRouter()
    /// 앱이 막 켜지는 중이라 화면이 아직 없을 때도 잃어버리지 않도록 화면이 가져갈 때까지 보관한다.
    @Published var pending: WidgetDeepLink?
}
