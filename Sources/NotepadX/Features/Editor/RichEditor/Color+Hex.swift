import AppKit
import SwiftUI

extension Color {
    /// 툴바 색상 피커에서 고른 색을 CSS에 바로 쓸 수 있는 "#rrggbb" 문자열로 바꾼다.
    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
