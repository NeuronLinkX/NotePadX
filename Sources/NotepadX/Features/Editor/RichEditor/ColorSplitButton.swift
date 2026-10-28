import AppKit
import SwiftUI

struct NamedColor: Identifiable, Equatable {
    let name: String
    let hex: String
    var id: String { hex }
}

enum ColorPalettes {
    /// 글자색: 흰 배경에서 또렷하게 읽히는 진한 색 위주.
    static let text: [NamedColor] = [
        NamedColor(name: "검정", hex: "#000000"),
        NamedColor(name: "진한 회색", hex: "#4B5563"),
        NamedColor(name: "빨강", hex: "#DC2626"),
        NamedColor(name: "주황", hex: "#EA580C"),
        NamedColor(name: "황토", hex: "#CA8A04"),
        NamedColor(name: "초록", hex: "#16A34A"),
        NamedColor(name: "청록", hex: "#0D9488"),
        NamedColor(name: "파랑", hex: "#2563EB"),
        NamedColor(name: "남색", hex: "#4338CA"),
        NamedColor(name: "보라", hex: "#9333EA"),
        NamedColor(name: "분홍", hex: "#DB2777"),
        NamedColor(name: "갈색", hex: "#92400E"),
    ]

    /// 형광펜: 글자가 그대로 읽히도록 밝고 옅은 배경색 위주.
    static let highlight: [NamedColor] = [
        NamedColor(name: "노랑", hex: "#FFF59D"),
        NamedColor(name: "연두", hex: "#D9F99D"),
        NamedColor(name: "초록", hex: "#BBF7D0"),
        NamedColor(name: "하늘", hex: "#BAE6FD"),
        NamedColor(name: "파랑", hex: "#BFDBFE"),
        NamedColor(name: "보라", hex: "#DDD6FE"),
        NamedColor(name: "분홍", hex: "#FBCFE8"),
        NamedColor(name: "빨강", hex: "#FECACA"),
        NamedColor(name: "주황", hex: "#FED7AA"),
        NamedColor(name: "회색", hex: "#E5E7EB"),
    ]

    /// 에디터가 돌려준 CSS 색("#rgb", "#rrggbb", "rgb(r, g, b)")을 "#RRGGBB"로 통일한다 —
    /// 붙여넣기한 문서에는 우리가 넣지 않은 표기가 섞여 있을 수 있다.
    static func normalizedHex(from css: String?) -> String? {
        guard var value = css?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return nil }
        if value.hasPrefix("rgb") {
            let numbers = value
                .drop(while: { $0 != "(" }).dropFirst()
                .prefix(while: { $0 != ")" })
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count >= 3 else { return nil }
            return String(format: "#%02X%02X%02X", numbers[0], numbers[1], numbers[2])
        }
        guard value.hasPrefix("#") else { return nil }
        value.removeFirst()
        if value.count == 3 { value = value.map { "\($0)\($0)" }.joined() }
        guard value.count == 6, UInt64(value, radix: 16) != nil else { return nil }
        return "#" + value.uppercased()
    }
}

/// 시스템 색상 패널을 직접 띄워 "사용자 지정" 색을 고른다. SwiftUI ColorPicker를 팝오버 안에
/// 넣으면 색상 패널이 뜨는 순간 팝오버가 닫히면서 선택이 끊기므로 NSColorPanel을 직접 쓴다.
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((String) -> Void)?

    func present(initialHex: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = false
        if let initial = Color(hex: initialHex) { panel.color = NSColor(initial) }
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(Color(nsColor: sender.color).hexString)
    }
}

/// 글자색/형광펜 공용 분할 버튼. 본체를 누르면 마지막에 쓴 색을 바로 적용하고, ▾를 누르면
/// 이름이 붙은 색 목록(+지우기, 사용자 지정)이 열린다. 두 버튼이 한눈에 구분되도록 미리보기를
/// 다르게 그린다 — 글자색은 "가"가 그 색으로, 형광펜은 "가" 뒤에 그 색 배경이 깔린다.
struct ColorSplitButton: View {
    enum Kind {
        case text, highlight

        var title: String { self == .text ? "글자색" : "형광펜" }
        var detail: String { self == .text ? "선택한 글자의 색을 바꿉니다" : "선택한 글자 뒤에 배경색을 칠합니다" }
        var palette: [NamedColor] { self == .text ? ColorPalettes.text : ColorPalettes.highlight }
        var defaultHex: String { self == .text ? "#DC2626" : "#FFF59D" }
        var storageKey: String { self == .text ? "notepadx.toolbar.lastTextColor" : "notepadx.toolbar.lastHighlightColor" }
        var clearTitle: String { self == .text ? "글자색 지우기" : "형광펜 지우기" }
    }

    let kind: Kind
    /// 지금 커서/선택 영역에 실제로 걸려 있는 색(없으면 nil).
    let currentCSSColor: String?
    let apply: (String) -> Void
    let clear: () -> Void

    @AppStorage private var lastHex: String
    @State private var isShowingPalette = false

    init(kind: Kind, currentCSSColor: String?, apply: @escaping (String) -> Void, clear: @escaping () -> Void) {
        self.kind = kind
        self.currentCSSColor = currentCSSColor
        self.apply = apply
        self.clear = clear
        _lastHex = AppStorage(wrappedValue: kind.defaultHex, kind.storageKey)
    }

    private var lastColor: Color { Color(hex: lastHex) ?? .yellow }
    private var currentHex: String? { ColorPalettes.normalizedHex(from: currentCSSColor) }

    var body: some View {
        HStack(spacing: 0) {
            Button { apply(lastHex) } label: { preview }
                .help("\(kind.title) — \(kind.detail) (마지막에 쓴 색)")
                .accessibilityLabel("\(kind.title) 적용")

            Button { isShowingPalette.toggle() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 12, height: 22)
                    .contentShape(Rectangle())
            }
            .help("\(kind.title) 색 고르기")
            .accessibilityLabel("\(kind.title) 색 고르기")
            .popover(isPresented: $isShowingPalette, arrowEdge: .bottom) { palettePopover }
        }
    }

    private var preview: some View {
        HStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(kind == .highlight ? lastColor : Color.clear)
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                Text("가")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(kind == .text ? lastColor : Color.black)
            }
            .frame(width: 24, height: 20)
            Text(kind.title)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
    }

    private var palettePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.headline)
                Text(kind.detail).font(.caption).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 6), spacing: 8) {
                ForEach(kind.palette) { swatch in
                    swatchButton(swatch)
                }
            }

            Divider()

            HStack {
                Button(kind.clearTitle) {
                    clear()
                    isShowingPalette = false
                }
                Spacer()
                Button("사용자 지정…") {
                    isShowingPalette = false
                    ColorPanelBridge.shared.present(initialHex: lastHex) { hex in
                        lastHex = hex
                        apply(hex)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 6 * 26 + 5 * 8 + 28)
    }

    @ViewBuilder
    private func swatchButton(_ swatch: NamedColor) -> some View {
        let color = Color(hex: swatch.hex) ?? .gray
        let isSelected = (currentHex ?? lastHex.uppercased()) == swatch.hex.uppercased()
        Button {
            lastHex = swatch.hex
            apply(swatch.hex)
            isShowingPalette = false
        } label: {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Self.isLight(swatch.hex) ? Color.black : Color.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(swatch.name)
        .accessibilityLabel("\(kind.title) \(swatch.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private static func isLight(_ hex: String) -> Bool {
        let nsColor = NSColor(Color(hex: hex) ?? .gray).usingColorSpace(.deviceRGB)
        guard let c = nsColor else { return true }
        return (0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent) > 0.6
    }
}
