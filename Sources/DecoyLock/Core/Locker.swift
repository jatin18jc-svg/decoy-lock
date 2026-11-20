import AppKit
import Foundation
import QuickLookThumbnailing

enum LockProblem: LocalizedError {
    case unsupported(String)
    case alreadyLocked(String)
    case notValid(String, String)
    case inUse(String, String)
    case unreadable(String)
    case missingDecoy(String)
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let n): return "\(n) can't be locked. Decoy Lock handles \(FileTypes.extensionList) files."
        case .alreadyLocked(let n): return "\(n) is already locked."
        case .notValid(let n, let ext): return "\(n) doesn't look like a working .\(ext) file, so it was left alone."
        case .inUse(let n, let app): return "\(n) is open in \(app). Close it there, then lock it."
        case .unreadable(let n): return "Decoy Lock couldn't read \(n)."
        case .missingDecoy(let n): return "The blank copy for \(n) is missing from the app. Reinstall Decoy Lock."
        case .verifyFailed(let n): return "\(n) didn't check out after locking, so the original was kept."
        }
    }
}

enum Locker {
    static func decoyBody(for type: SupportedType, bundle: Bundle = .main) -> Data? {
        let name = (type.decoyResource as NSString).deletingPathExtension
        let ext = (type.decoyResource as NSString).pathExtension
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Decoys") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Why this file can't be locked right now, or nil if it can.
    static func problem(with url: URL, checkInUse: Bool = true) -> LockProblem? {
        let name = url.lastPathComponent
        guard let type = FileTypes.type(for: url) else { return .unsupported(name) }
        guard let prefix = FileOps.readPrefix(url, length: FileTypes.probeLength),
              let size = FileOps.size(url) else { return .unreadable(name) }
        if !type.isPlain(prefix: prefix) {
            return LockedFormat.couldBeLocked(size: size) ? .alreadyLocked(name) : .notValid(name, type.ext)
        }
        if checkInUse, let pid = FileOps.processesUsing(url).first {
            let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "another app"
            return .inUse(name, app)
        }
        return nil
    }

    /// Locks a file in place. Same path, same name, same dates; the original bytes are
    /// only replaced once the locked version has been decrypted and checked.
    static func lock(_ url: URL, pair: Pair, checkInUse: Bool = true, blankThumbnail: Bool = Prefs.blankThumbnails) throws {
        let name = url.lastPathComponent
        if let problem = problem(with: url, checkInUse: checkInUse) { throw problem }
        guard let type = FileTypes.type(for: url) else { throw LockProblem.unsupported(name) }
        guard let decoy = decoyBody(for: type) else { throw LockProblem.missingDecoy(name) }
        guard let body = try? Data(contentsOf: url) else { throw LockProblem.unreadable(name) }

        let dates = FileOps.dates(url)
        let locked = try LockedFormat.lock(body: body, name: name, type: type, decoyBody: decoy,
                                           realPassword: pair.real, decoyPassword: pair.decoy,
                                           quarantine: FileOps.Quarantine.read(url))
        guard LockedFormat.verify(locked, realBody: body, decoyBody: decoy) else { throw LockProblem.verifyFailed(name) }
        try FileOps.replaceContents(of: url, with: locked.data, dates: dates)
        OpenWith.bindToThisApp(url)

        if blankThumbnail { Thumbnails.applyBlank(to: url, type: type, decoy: decoy) }
    }

    /// For a file that's already locked: clears the quarantine flag (which stops it from
    /// opening at all) and points it back at Decoy Lock. Returns true if anything changed.
    @discardableResult
    static func repair(_ url: URL) -> Bool {
        let flagged = FileOps.Quarantine.read(url) != nil
        let unbound = !OpenWith.isBound(url)
        if flagged { FileOps.Quarantine.remove(url) }
        if unbound { OpenWith.bindToThisApp(url) }
        return flagged || unbound
    }
}

/// The per-file "Open with" setting, the same one Finder writes when you change
/// Get Info > Open with for a single file without clicking Change All. Locked files
/// open in Decoy Lock; every other file of the type keeps opening in its usual app.
/// It's an extended attribute, so it survives edits being saved back (those copy
/// extended attributes) and travels with the file to another Mac with Decoy Lock.
enum OpenWith {
    static let attribute = "com.apple.LaunchServices.OpenWith"

    @discardableResult
    static func bindToThisApp(_ url: URL) -> Bool {
        let plist: [String: Any] = [
            "version": 0,
            "bundleidentifier": Bundle.main.bundleIdentifier ?? BuildTools.bundleID,
            "path": Bundle.main.bundlePath,
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else { return false }
        return data.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, data.count, 0, 0) } == 0
    }

    static func isBound(_ url: URL) -> Bool {
        getxattr(url.path, attribute, nil, 0, 0, 0) > 0
    }
}

/// Finder shows content thumbnails for normal PDFs and Office files, and a plain type
/// icon for files it can't read, which would include locked ones. This optional fix
/// gives a locked file the thumbnail of its blank decoy, so it looks like an empty file.
enum Thumbnails {
    static func applyBlank(to url: URL, type: SupportedType, decoy: Data) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString)")
        let sample = dir.appendingPathComponent("Blank.\(type.ext)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try decoy.write(to: sample)
        } catch { return }

        let request = QLThumbnailGenerator.Request(fileAt: sample, size: CGSize(width: 512, height: 512),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            DispatchQueue.main.async {
                if let image = rep?.nsImage {
                    NSWorkspace.shared.setIcon(framed(image), forFile: url.path, options: [])
                }
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }

    /// Finder draws a thin frame and shadow around real thumbnails but shows custom
    /// icons as-is, so the frame is drawn here to match.
    private static func framed(_ image: NSImage) -> NSImage {
        let canvas = NSSize(width: 512, height: 512)
        let fit = min((canvas.width - 40) / image.size.width, (canvas.height - 40) / image.size.height)
        let size = NSSize(width: image.size.width * fit, height: image.size.height * fit)
        let rect = NSRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                          width: size.width, height: size.height)
        return NSImage(size: canvas, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
            NSColor.white.setFill()
            rect.fill()
            NSGraphicsContext.restoreGraphicsState()
            image.draw(in: rect)
            NSColor(white: 0, alpha: 0.16).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            return true
        }
    }
}
