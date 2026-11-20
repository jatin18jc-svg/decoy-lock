import AppKit
import Foundation

/// Finds the app each type is handed to, and gives back any type Decoy Lock is the default for.
final class DefaultApps {
    static let shared = DefaultApps()

    private let myID = Bundle.main.bundleIdentifier ?? "com.decoylock.app"

    func isUs(_ url: URL?) -> Bool {
        guard let url else { return false }
        return Bundle(url: url)?.bundleIdentifier == myID
    }

    func currentDefault(_ type: SupportedType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type.utType)
    }

    func isOpener(_ type: SupportedType) -> Bool {
        isUs(currentDefault(type))
    }

    /// Older builds made Decoy Lock the default for whole file types. Settings and
    /// Uninstall use this to offer handing those types back.
    var isOpenerForAny: Bool { FileTypes.all.contains(where: isOpener) }

    /// The app that should actually show the file.
    func handOffApp(for type: SupportedType) -> URL? {
        if let current = currentDefault(type), !isUs(current) { return current }
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: type.utType).filter { !isUs($0) }
        for id in type.preferredApps {
            if let match = candidates.first(where: { Bundle(url: $0)?.bundleIdentifier == id }) { return match }
        }
        return candidates.first
    }

    func appName(_ url: URL?) -> String {
        guard let url else { return "no app" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    @MainActor
    func restore() async -> [String] {
        var failures: [String] = []
        for type in FileTypes.all where isOpener(type) {
            guard let app = handOffApp(for: type) else {
                failures.append("\(type.label): no other app can open these.")
                continue
            }
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type.utType)
            } catch {
                failures.append("\(type.label): \(error.localizedDescription)")
            }
        }
        return failures
    }
}
