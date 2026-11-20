import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A small document with two eyes, drawn as a template so it follows the menu bar's colour.
enum MenuBarGlyph {
    static func image(awake: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 5.2, y: 2.5))
            body.line(to: NSPoint(x: 11.2, y: 2.5))
            body.line(to: NSPoint(x: 14.5, y: 5.8))
            body.line(to: NSPoint(x: 14.5, y: 13.6))
            body.appendArc(withCenter: NSPoint(x: 12.6, y: 13.6), radius: 1.9, startAngle: 0, endAngle: 90)
            body.line(to: NSPoint(x: 5.4, y: 15.5))
            body.appendArc(withCenter: NSPoint(x: 5.4, y: 13.6), radius: 1.9, startAngle: 90, endAngle: 180)
            body.line(to: NSPoint(x: 3.5, y: 4.4))
            body.appendArc(withCenter: NSPoint(x: 5.4, y: 4.4), radius: 1.9, startAngle: 180, endAngle: 270)
            body.close()
            body.lineWidth = 1.4
            body.lineJoinStyle = .round
            NSColor.black.setStroke()
            body.stroke()

            NSColor.black.setFill()
            let h: CGFloat = awake ? 3.2 : 2.5
            NSBezierPath(ovalIn: NSRect(x: 6.3, y: 8.2, width: 1.9, height: h)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.9, y: 8.2, width: 1.9, height: h)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Decoy Lock"
        return image
    }
}

/// The menu bar icon. Click for the popover; drop files straight onto it to lock them.
final class StatusItemController: NSObject, NSWindowDelegate, NSDraggingDestination {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    override init() {
        super.init()
        if let button = item.button {
            button.image = MenuBarGlyph.image()
            button.target = self
            button.action = #selector(toggle)
            // Status buttons can't be subclassed, but their window passes drags to its delegate.
            button.window?.registerForDraggedTypes([.fileURL])
            button.window?.delegate = self
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuPopoverView(
            onLock: { [weak self] urls in
                self?.popover.performClose(nil)
                Windows.showLock(urls)
            },
            onSettings: { [weak self] in
                self?.popover.performClose(nil)
                Windows.showSettings()
            }))
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(item)
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(sender).isEmpty else { return [] }
        item.button?.image = MenuBarGlyph.image(awake: true)
        item.button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        item.button?.image = MenuBarGlyph.image()
        item.button?.highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingExited(sender)
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        DispatchQueue.main.async { Windows.showLock(urls) }
        return true
    }
}

struct MenuPopoverView: View {
    var onLock: ([URL]) -> Void
    var onSettings: () -> Void
    @ViewState private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropZone

            Button {
                chooseFiles()
            } label: {
                Label("Choose Files to Lock…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                MenuRow(title: "Settings…", shortcut: "⌘,", action: onSettings)
                MenuRow(title: "Quit Decoy Lock", shortcut: "⌘Q") { AppDelegate.confirmQuit() }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var dropZone: some View {
        HStack(spacing: 14) {
            Mascot(mood: targeted ? .alert : .idle, size: 66)
            VStack(alignment: .leading, spacing: 3) {
                Text(targeted ? "Let go to lock" : "Drop files to lock")
                    .font(Fonts.heading(15))
                    .foregroundStyle(Palette.ink)
                Text(FileTypes.extensionList)
                    .font(Fonts.small)
                    .foregroundStyle(Palette.dusk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 104)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.fur))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(targeted ? Palette.action : Palette.dusk.opacity(0.45),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .animation(.easeOut(duration: 0.15), value: targeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            load(providers)
            return true
        }
    }

    private func load(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { if !urls.isEmpty { onLock(urls) } }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = FileTypes.all.map(\.utType)
        panel.prompt = "Lock"
        panel.message = "Choose files to lock. They stay where they are, with the same names."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty { onLock(panel.urls) }
    }
}

private struct MenuRow: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(.secondary)
            }
            .font(Fonts.body)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Palette.furDeep.opacity(0.7) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
