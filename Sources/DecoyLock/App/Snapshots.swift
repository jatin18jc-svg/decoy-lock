import AppKit
import SwiftUI

/// `DecoyLock --snapshot <dir>`: renders every screen and mascot mood to PNG, for
/// design review and the README. Uses sample files only; nothing is locked or changed.
enum Snapshots {
    @MainActor
    static func run(to dir: String) -> Bool {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let moods: [(String, Mood)] = [("idle", .idle), ("covering", .covering), ("peeking", .peeking),
                                       ("possum", .possum), ("happy", .happy), ("alert", .alert), ("worried", .worried)]
        let strip = HStack(spacing: 28) {
            ForEach(moods, id: \.0) { name, mood in
                VStack(spacing: 10) {
                    Mascot(mood: mood, size: 120).frame(width: 130, height: 130)
                    Text(name).font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(30)
        .background(Palette.fur)
        let renderer = ImageRenderer(content: strip)
        renderer.scale = 2
        if let cg = renderer.cgImage { write(NSBitmapImageRep(cgImage: cg), to: out.appendingPathComponent("moods.png")) }

        let sample = FileManager.default.temporaryDirectory.appendingPathComponent("Budget.xlsx")
        if let decoy = Locker.decoyBody(for: FileTypes.all[0]) { try? decoy.write(to: sample) }

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            NSApp.appearance = NSAppearance(named: appearance)
            snap(OnboardingView(close: {}), "onboarding-\(suffix)", out)
            snap(LockView(model: LockModel(urls: [sample]), close: {}), "lock-\(suffix)", out)
            snap(SettingsView(), "settings-\(suffix)", out)
            snap(ShowPairSheet(pairs: [Pair(real: "correct horse ", decoy: "nothing here"),
                                       Pair(real: "old-secret-1", decoy: "groceries")], done: {}), "showpair-\(suffix)", out)
            snap(MenuPopoverView(onLock: { _ in }, onSettings: {}), "popover-\(suffix)", out)
            let model = PromptModel()
            snap(PasswordPromptView(fileName: "Budget.xlsx", icon: NSWorkspace.shared.icon(forFile: sample.path),
                                    model: model, onOpen: {}, onCancel: {}), "prompt-\(suffix)", out)
            model.error = "Incorrect password"
            snap(PasswordPromptView(fileName: "Budget.xlsx", icon: NSWorkspace.shared.icon(forFile: sample.path),
                                    model: model, onOpen: {}, onCancel: {}), "prompt-wrong-\(suffix)", out)
        }
        try? FileManager.default.removeItem(at: sample)
        return true
    }

    @MainActor
    private static func snap<V: View>(_ view: V, _ name: String, _ dir: URL) {
        if let only = ProcessInfo.processInfo.environment["SNAP_ONLY"], !name.hasPrefix(only) { return }
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        write(rep, to: dir.appendingPathComponent("\(name).png"))
        window.contentView = nil
        window.close()
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
