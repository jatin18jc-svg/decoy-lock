import AppKit
import SwiftUI

/// The only window someone looking over your shoulder will see. It is deliberately
/// plain and system-like: no mascot, no brand colour, no app name. The real password
/// and the decoy word take the same path through it and close it the same way.
final class PromptModel: ObservableObject {
    @Published var password = ""
    @Published var error: String?
    @Published var busy = false
    @Published var shakes: CGFloat = 0
}

struct PasswordPromptView: View {
    let fileName: String
    let icon: NSImage
    @ObservedObject var model: PromptModel
    var onOpen: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 64, height: 64)
                .padding(.bottom, 12)

            Text("Enter password to open this file.")
                .font(.system(size: 13, weight: .bold))
                .multilineTextAlignment(.center)
            Text(fileName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 3)

            SecureField("Password", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(onOpen)
                .disabled(model.busy)
                .modifier(Shake(animatableData: model.shakes))
                .padding(.top, 14)

            Text(model.error ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .systemRed))
                .frame(height: 16)
                .padding(.top, 4)

            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity)
                Button("Open", action: onOpen)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(width: 272)
        .onAppear { focused = true }
    }
}

final class PasswordPrompt: NSObject, NSWindowDelegate {
    private static var open: [PasswordPrompt] = []

    private let url: URL
    private let type: SupportedType
    private let model = PromptModel()
    private var panel: NSPanel!

    static func present(for url: URL, type: SupportedType) {
        if let existing = open.first(where: { $0.url == url }) {
            NSApp.activate(ignoringOtherApps: true)
            existing.panel.makeKeyAndOrderFront(nil)
            return
        }
        let prompt = PasswordPrompt(url: url, type: type)
        open.append(prompt)
        prompt.show()
    }

    private init(url: URL, type: SupportedType) {
        self.url = url
        self.type = type
        super.init()
    }

    private func show() {
        let view = PasswordPromptView(
            fileName: url.lastPathComponent,
            icon: NSWorkspace.shared.icon(forFile: url.path),
            model: model,
            onOpen: { [weak self] in self?.submit() },
            onCancel: { [weak self] in self?.panel.close() })
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize

        panel = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                        styleMask: [.titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = url.lastPathComponent
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.delegate = self
        panel.center()
        // Opened from Finder, macOS may not let a background app come forward, so the
        // box floats and orders itself in front regardless.
        panel.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func windowWillClose(_ notification: Notification) {
        PasswordPrompt.open.removeAll { $0 === self }
    }

    private func submit() {
        guard !model.busy else { return }
        model.busy = true
        model.error = nil
        let password = model.password
        let url = self.url
        let type = self.type
        let started = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var opened: (file: URL, app: URL)?
            var failure: String?

            if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
               let app = DefaultApps.shared.handOffApp(for: type) {
                let outcome = LockedFormat.attempt(data, password: password)
                let name = url.lastPathComponent
                do {
                    switch outcome {
                    case .real(let body, let keys):
                        opened = (try SessionManager.shared.begin(body: body, name: name, type: type, keys: keys, original: url,
                                                                  app: app, quarantine: keys.header.q), app)
                    case .decoy(let body, let header):
                        opened = (try SessionManager.shared.begin(body: body, name: name, type: type, keys: nil, original: url,
                                                                  app: app, quarantine: header.q), app)
                    case .incorrect:
                        failure = "Incorrect password"
                    }
                } catch {
                    failure = "This file couldn't be opened."
                }
            } else {
                failure = "This file couldn't be opened."
            }

            // Real and decoy finish on the same beat, however long the work took.
            let wait = max(0, 0.55 - Date().timeIntervalSince(started))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                guard let self else { return }
                if let opened {
                    self.panel.close()
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.open([opened.file], withApplicationAt: opened.app, configuration: config)
                } else {
                    self.model.busy = false
                    self.model.password = ""
                    self.model.error = failure
                    withAnimation(.linear(duration: 0.4)) { self.model.shakes += 1 }
                    NSSound.beep()
                }
            }
        }
    }
}

/// Decides, for every file the system hands us, whether it needs the password box.
enum Opener {
    static func open(_ url: URL) {
        guard let type = FileTypes.type(for: url) else {
            NSWorkspace.shared.open(url)
            return
        }
        let size = FileOps.size(url) ?? 0
        let prefix = FileOps.readPrefix(url, length: FileTypes.probeLength) ?? Data()
        if type.isPlain(prefix: prefix) || !LockedFormat.couldBeLocked(size: size) {
            passThrough(url, type: type)
        } else {
            PasswordPrompt.present(for: url, type: type)
        }
    }

    /// Normal files go straight to their usual app with nothing shown.
    static func passThrough(_ url: URL, type: SupportedType) {
        guard let app = DefaultApps.shared.handOffApp(for: type) else {
            Alerts.show(title: "No app can open \(url.lastPathComponent)",
                        message: "Install an app that opens .\(type.ext) files, then try again.")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
    }
}

enum Alerts {
    static func show(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
