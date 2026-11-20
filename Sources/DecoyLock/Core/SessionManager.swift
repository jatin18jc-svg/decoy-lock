import AppKit
import CryptoKit
import Foundation

/// One unlocked copy sitting in the private temp folder while its app has it open.
final class EditSession {
    let tempDir: URL
    let tempURL: URL
    let type: SupportedType
    /// nil for a decoy copy or a leftover from a previous run: never written back.
    let keys: RealSessionKeys?
    let appBundleID: String?
    let started = Date()

    var bookmark: Data?
    var originalURL: URL?
    var lastDigest: Data?
    var lastStamp: String?
    var sawHandle = false
    var misses = 0
    var reportedError = false
    var dirWatch: DispatchSourceFileSystemObject?
    var fileWatch: DispatchSourceFileSystemObject?
    var pending: DispatchWorkItem?

    init(tempDir: URL, tempURL: URL, type: SupportedType, keys: RealSessionKeys?, appBundleID: String?) {
        self.tempDir = tempDir
        self.tempURL = tempURL
        self.type = type
        self.keys = keys
        self.appBundleID = appBundleID
    }
}

/// Watches unlocked copies, writes saves back into the locked file, and deletes
/// the copies once their app lets go of them.
final class SessionManager {
    static let shared = SessionManager()

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("dl", isDirectory: true)
    private let queue = DispatchQueue(label: "decoylock.sessions")
    private var sessions: [EditSession] = []
    private var timer: DispatchSourceTimer?

    var activeRealCount: Int { queue.sync { sessions.filter { $0.keys != nil }.count } }

    /// Writes the unlocked copy and starts watching it. Returns its path.
    func begin(body: Data, name: String, type: SupportedType, keys: RealSessionKeys?, original: URL, app: URL,
               quarantine: String? = nil) throws -> URL {
        try queue.sync {
            let fm = FileManager.default
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let dir = root.appendingPathComponent(String(UUID().uuidString.prefix(13)), isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let file = dir.appendingPathComponent(name)
            try body.write(to: file)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            if let quarantine { FileOps.Quarantine.write(quarantine, to: file) }

            let session = EditSession(tempDir: dir, tempURL: file, type: type, keys: keys,
                                      appBundleID: Bundle(url: app)?.bundleIdentifier)
            if keys != nil {
                session.originalURL = original
                session.bookmark = try? original.bookmarkData()
                session.lastDigest = Data(SHA256.hash(data: body))
                session.lastStamp = FileOps.stamp(file)
                watch(session)
            }
            sessions.append(session)
            startTimer()
            return file
        }
    }

    /// At launch: delete copies nothing has open; keep an eye on the rest until they close.
    func cleanUpLeftovers() {
        queue.async { [self] in
            let fm = FileManager.default
            guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
            for dir in dirs {
                let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
                let openFile = files.first { !FileOps.processesUsing($0).isEmpty }
                if let openFile, let type = FileTypes.type(for: openFile) {
                    let leftover = EditSession(tempDir: dir, tempURL: openFile, type: type, keys: nil, appBundleID: nil)
                    leftover.sawHandle = true
                    sessions.append(leftover)
                    startTimer()
                } else {
                    try? fm.removeItem(at: dir)
                }
            }
        }
    }

    /// Last chance to write back before the app quits.
    func flushAll() {
        queue.sync { for s in sessions where s.keys != nil { syncIfChanged(s, force: true) } }
    }

    // MARK: Watching

    private func watch(_ s: EditSession) {
        let dfd = open(s.tempDir.path, O_EVTONLY)
        if dfd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dfd, eventMask: [.write, .rename, .delete], queue: queue)
            src.setEventHandler { [weak self, weak s] in
                guard let self, let s else { return }
                self.scheduleSync(s)
            }
            src.setCancelHandler { close(dfd) }
            src.resume()
            s.dirWatch = src
        }
        attachFileWatch(s)
    }

    /// Apps that save by writing a new file and renaming it into place leave the
    /// old watcher pointing at nothing, so this is reattached after every change.
    private func attachFileWatch(_ s: EditSession) {
        s.fileWatch?.cancel()
        s.fileWatch = nil
        let fd = open(s.tempURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        src.setEventHandler { [weak self, weak s] in
            guard let self, let s else { return }
            self.scheduleSync(s)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        s.fileWatch = src
    }

    private func scheduleSync(_ s: EditSession) {
        s.pending?.cancel()
        let work = DispatchWorkItem { [weak self, weak s] in
            guard let self, let s else { return }
            self.attachFileWatch(s)
            self.syncIfChanged(s, force: false)
        }
        s.pending = work
        queue.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: 3, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    private func poll() {
        for s in sessions {
            if s.keys != nil { syncIfChanged(s, force: false) }

            if !FileOps.processesUsing(s.tempURL).isEmpty {
                s.sawHandle = true
                s.misses = 0
                continue
            }
            let appRunning = s.appBundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
            if s.sawHandle {
                // A few misses in a row, so a save that briefly closes the file doesn't count.
                s.misses += 1
                if s.misses >= 3 { finish(s) }
            } else if !appRunning && Date().timeIntervalSince(s.started) > 15 {
                // Apps that don't hold the file open: wait for the app itself to quit.
                finish(s)
            }
        }
        if sessions.isEmpty {
            timer?.cancel()
            timer = nil
        }
    }

    private func finish(_ s: EditSession) {
        if s.keys != nil { syncIfChanged(s, force: true) }
        s.pending?.cancel()
        s.dirWatch?.cancel()
        s.fileWatch?.cancel()
        try? FileManager.default.removeItem(at: s.tempDir)
        sessions.removeAll { $0 === s }
    }

    // MARK: Writing back

    private func syncIfChanged(_ s: EditSession, force: Bool) {
        guard let keys = s.keys else { return }
        let stamp = FileOps.stamp(s.tempURL)
        guard stamp != nil, force || stamp != s.lastStamp else { return }
        guard let data = try? Data(contentsOf: s.tempURL), !data.isEmpty,
              s.type.isPlain(prefix: data.prefix(FileTypes.probeLength)),
              s.type.looksComplete(data)
        else { return }   // mid-save; the next event or poll picks it up

        let digest = Data(SHA256.hash(data: data))
        s.lastStamp = stamp
        guard digest != s.lastDigest else { return }

        do {
            let target = try resolveOriginal(s)
            let current = try Data(contentsOf: target)
            let sealed = try LockedFormat.reseal(current: current, newBody: data, keys: keys)
            try FileOps.replaceContents(of: target, with: sealed,
                                        dates: .init(created: FileOps.dates(target).created, modified: Date()))
            s.lastDigest = digest
            s.originalURL = target
            s.bookmark = (try? target.bookmarkData()) ?? s.bookmark
        } catch {
            guard !s.reportedError else { return }
            s.reportedError = true
            let name = s.tempURL.lastPathComponent
            DispatchQueue.main.async {
                Alerts.show(
                    title: "Changes to \(name) weren't locked back in",
                    message: "\(error.localizedDescription)\n\nKeep the file open and use File > Save As in its app to save a copy somewhere safe, then lock that copy.")
            }
        }
    }

    private func resolveOriginal(_ s: EditSession) throws -> URL {
        if let bookmark = s.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) { return url }
        }
        guard let url = s.originalURL, FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "The locked file was moved or deleted."])
        }
        return url
    }
}
