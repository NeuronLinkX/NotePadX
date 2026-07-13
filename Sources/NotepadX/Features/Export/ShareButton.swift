import AppKit
import SwiftUI

/// NSSharingServicePicker는 화면 위의 NSView를 기준점으로 띄워야 해서, SwiftUI Button만으로는
/// 만들 수 없다 — 얇은 NSViewRepresentable로 감싼다.
struct ShareButton: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "공유…", target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .rounded
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.url = url
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var url: URL
        init(url: URL) { self.url = url }

        @objc func share(_ sender: NSButton) {
            let picker = NSSharingServicePicker(items: [url])
            picker.delegate = self
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
