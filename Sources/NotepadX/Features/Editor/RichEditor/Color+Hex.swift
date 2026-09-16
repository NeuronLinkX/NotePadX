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

    /// 다이어그램 편집기 저장용 — 투명한 채우기("텍스트만" 도형)를 표현할 수 있도록
    /// 알파까지 포함한 "#rrggbbaa" 문자열로 바꾼다.
    var hexStringWithAlpha: String {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        let a = Int((nsColor.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    /// "#rrggbb" 또는 "#rrggbbaa" 문자열을 Color로 되돌린다. 형식이 안 맞으면 nil.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let parsed = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let r, g, b, a: Double
        if hasAlpha {
            r = Double((parsed >> 24) & 0xFF) / 255
            g = Double((parsed >> 16) & 0xFF) / 255
            b = Double((parsed >> 8) & 0xFF) / 255
            a = Double(parsed & 0xFF) / 255
        } else {
            r = Double((parsed >> 16) & 0xFF) / 255
            g = Double((parsed >> 8) & 0xFF) / 255
            b = Double(parsed & 0xFF) / 255
            a = 1
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }
}
