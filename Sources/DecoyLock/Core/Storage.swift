import AppKit
import Foundation
import LocalAuthentication
import Security
import ServiceManagement

enum PrefKey {
    static let onboardingDone = "onboardingDone"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let blankThumbnails = "blankThumbnails"
}

enum Prefs {
    private static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [PrefKey.showMenuBarIcon: true, PrefKey.blankThumbnails: false])
    }

    static var onboardingDone: Bool {
        get { d.bool(forKey: PrefKey.onboardingDone) }
        set { d.set(newValue, forKey: PrefKey.onboardingDone) }
    }

    static var showMenuBarIcon: Bool {
        get { d.bool(forKey: PrefKey.showMenuBarIcon) }
        set { d.set(newValue, forKey: PrefKey.showMenuBarIcon) }
    }

    static var blankThumbnails: Bool {
        get { d.bool(forKey: PrefKey.blankThumbnails) }
        set { d.set(newValue, forKey: PrefKey.blankThumbnails) }
    }

    static func reset() {
        for key in [PrefKey.onboardingDone, PrefKey.showMenuBarIcon, PrefKey.blankThumbnails, "originalApps"] {
            d.removeObject(forKey: key)
        }
    }
}

// MARK: - The usual pair

struct Pair: Codable, Equatable {
    var real: String
    var decoy: String
}

/// The usual pair lives in the login Keychain. A verifier alone wouldn't be enough:
/// locking a new file needs fresh keys from new salts, and that needs the passwords.
/// The Keychain keeps them encrypted at rest and never in plain text on disk.
///
/// Earlier usual pairs are kept too (newest first), so a file locked before you changed
/// your pair can still be recovered with Show Pair in Settings.
enum PairStore {
    private static let service = "Decoy Lock"
    private static let current = "usual-pair"
    private static let earlier = "earlier-pairs"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func write(_ data: Data, to account: String) throws {
        SecItemDelete(query(account) as CFDictionary)
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrLabel as String] = "Decoy Lock"
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "The Keychain wouldn't save the pair (error \(status))."])
        }
    }

    static var exists: Bool {
        var q = query(current)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> Pair? {
        read(current).flatMap { try? JSONDecoder().decode(Pair.self, from: $0) }
    }

    static func earlierPairs() -> [Pair] {
        read(earlier).flatMap { try? JSONDecoder().decode([Pair].self, from: $0) } ?? []
    }

    static func save(_ pair: Pair) throws {
        if let old = load(), old != pair {
            let history = [old] + earlierPairs().filter { $0 != old && $0 != pair }
            try write(JSONEncoder().encode(history), to: earlier)
        }
        try write(JSONEncoder().encode(pair), to: current)
    }

    static func delete() {
        SecItemDelete(query(current) as CFDictionary)
        SecItemDelete(query(earlier) as CFDictionary)
    }
}

/// "Is this really you?" with Touch ID, Apple Watch or the Mac's login password.
enum OwnerCheck {
    static func confirm(_ reason: String, then done: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            done(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

/// Rules for a new pair, shared by every screen that sets one.
enum PairRules {
    static let minimumRealLength = 8

    static func problem(real: String, confirm: String, decoy: String) -> String? {
        if real.isEmpty { return "Type a real password." }
        if real.count < minimumRealLength { return "Use at least \(minimumRealLength) characters for the real password." }
        if confirm != real { return "The two real passwords don't match." }
        if decoy.isEmpty { return "Type a decoy word." }
        if decoy == real { return "The decoy word has to be different from the real password." }
        return nil
    }

    /// Not a problem, just worth knowing.
    static func note(real: String, decoy: String) -> String? {
        let edges: (String) -> Bool = { $0.first?.isWhitespace == true || $0.last?.isWhitespace == true }
        if edges(real) { return "Your real password starts or ends with a space. That's allowed, so remember it." }
        if edges(decoy) { return "Your decoy word starts or ends with a space. That's allowed, so remember it." }
        return nil
    }
}

// MARK: - Login item

enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Decoy Lock: login item change failed: \(error.localizedDescription)")
        }
    }
}
