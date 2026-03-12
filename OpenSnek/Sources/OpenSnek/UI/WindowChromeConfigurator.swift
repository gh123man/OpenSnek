import SwiftUI
import AppKit

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            configure(window)
        }
    }

    private func configure(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }
        window.isMovableByWindowBackground = true
        installTitlebarIconIfNeeded(window)
    }

    private func installTitlebarIconIfNeeded(_ window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: {
            $0.identifier == OpenSnekBranding.titlebarAccessoryIdentifier
        }) else {
            return
        }
        guard let menuIcon = OpenSnekBranding.menuIcon else { return }

        let imageView = NSImageView(image: menuIcon)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 16, height: 14))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 16),
            container.heightAnchor.constraint(equalToConstant: 14),
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.identifier = OpenSnekBranding.titlebarAccessoryIdentifier
        accessory.layoutAttribute = .left
        accessory.view = container
        window.addTitlebarAccessoryViewController(accessory)
    }
}
