import Darwin
import Foundation

enum FileOps {
    struct Dates {
        var created: Date?
        var modified: Date?
    }

    static func readPrefix(_ url: URL, length: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: length)) ?? Data()
    }

    static func size(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    }

    static func dates(_ url: URL) -> Dates {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return Dates(created: attrs?[.creationDate] as? Date, modified: attrs?[.modificationDate] as? Date)
    }

    /// A cheap fingerprint for spotting saves without reading the whole file.
    static func stamp(_ url: URL) -> String? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return "\(st.st_ino)-\(st.st_size)-\(st.st_mtimespec.tv_sec)-\(st.st_mtimespec.tv_nsec)"
    }

    /// Replaces a file's contents without ever leaving a half-written file at its path:
    /// write a hidden sibling, copy over tags, custom icons and other extended attributes,
    /// then rename it over the original in one step.
    static func replaceContents(of url: URL, with data: Data, dates: Dates) throws {
        let fm = FileManager.default
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8)).tmp")
        let attrs = try fm.attributesOfItem(atPath: url.path)
        try data.write(to: tmp, options: .withoutOverwriting)
        _ = copyfile(url.path, tmp.path, nil, copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL))
        if let perms = attrs[.posixPermissions] {
            try? fm.setAttributes([.posixPermissions: perms], ofItemAtPath: tmp.path)
        }
        if rename(tmp.path, url.path) != 0 {
            let code = errno
            unlink(tmp.path)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        // Locked files must never carry the quarantine flag (see BlobHeader.q).
        removexattr(url.path, Quarantine.attribute, 0)
        var set: [FileAttributeKey: Any] = [:]
        if let c = dates.created { set[.creationDate] = c }
        if let m = dates.modified { set[.modificationDate] = m }
        if !set.isEmpty { try? fm.setAttributes(set, ofItemAtPath: url.path) }
    }

    enum Quarantine {
        static let attribute = "com.apple.quarantine"

        static func read(_ url: URL) -> String? {
            let size = getxattr(url.path, attribute, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            guard getxattr(url.path, attribute, &buffer, size, 0, 0) == size else { return nil }
            return String(decoding: buffer, as: UTF8.self)
        }

        static func write(_ value: String, to url: URL) {
            let bytes = Array(value.utf8)
            setxattr(url.path, attribute, bytes, bytes.count, 0, 0)
        }

        static func remove(_ url: URL) {
            removexattr(url.path, attribute, 0)
        }
    }

    /// Process IDs that have the file open, via lsof.
    static func processesUsing(_ url: URL) -> [pid_t] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-t", "--", url.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        // Not waitUntilExit(): it spins the run loop, and on the main thread that can
        // start a SwiftUI layout pass in the middle of another one.
        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        let me = getpid()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0) }
            .filter { $0 != me }
    }
}
