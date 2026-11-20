import AppKit
import SwiftUI

/// Owns the app's few windows. They're plain NSWindows hosting SwiftUI, because a
/// background helper with no Dock icon needs to bring them forward by hand.
enum Windows {
    private static var onboarding: NSWindow?
    private static var settings: NSWindow?
    private static var lockWindows: [NSWindow] = []
    private static var closers: [ObjectIdentifier: WindowCloser] = [:]

    static func showOnboarding() {
        if let w = onboarding { return bringForward(w) }
        let w = makeWindow(title: "Welcome to Decoy Lock", stage: true)
        w.contentView = NSHostingView(rootView: OnboardingView(close: { [weak w] in w?.close() }))
        onboarding = w
        track(w) { onboarding = nil }
        present(w)
    }

    static func showSettings() {
        if let w = settings { return bringForward(w) }
        let w = makeWindow(title: "Decoy Lock Settings", stage: true)
        w.contentView = NSHostingView(rootView: SettingsView())
        settings = w
        track(w) { settings = nil }
        present(w)
    }

    static func showLock(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let w = makeWindow(title: "Lock Files", stage: false)
        // Built here, not inside the view: it checks files on disk, which shouldn't
        // happen while SwiftUI is mid-update.
        let model = LockModel(urls: urls)
        w.contentView = NSHostingView(rootView: LockView(model: model, close: { [weak w] in w?.close() }))
        lockWindows.append(w)
        track(w) { lockWindows.removeAll { $0 === w } }
        present(w)
    }

    private static func makeWindow(title: String, stage: Bool) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = title
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.standardWindowButton(.miniaturizeButton)?.isHidden = true
        w.standardWindowButton(.zoomButton)?.isHidden = true
        return w
    }

    private static func present(_ w: NSWindow) {
        if let size = w.contentView?.fittingSize, size.width > 0 { w.setContentSize(size) }
        w.center()
        bringForward(w)
    }

    private static func bringForward(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private static func track(_ w: NSWindow, onClose: @escaping () -> Void) {
        let closer = WindowCloser(onClose: onClose)
        closers[ObjectIdentifier(w)] = closer
        w.delegate = closer
        closer.release = { closers[ObjectIdentifier(w)] = nil }
    }
}

private final class WindowCloser: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    var release: (() -> Void)?
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) {
        onClose()
        release?()
    }
}
