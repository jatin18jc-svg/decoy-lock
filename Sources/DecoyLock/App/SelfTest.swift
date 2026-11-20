import Foundation

/// `Decoy Lock.app/Contents/MacOS/DecoyLock --selftest [--large]`
/// Exercises the file format and in-place locking on scratch files. Touches no
/// Keychain, no default apps and no real documents.
enum SelfTest {
    private static var failures = 0

    private static func check(_ ok: Bool, _ label: String) {
        print(ok ? "  ok    \(label)" : "  FAIL  \(label)")
        if !ok { failures += 1 }
    }

    private static func time<T>(_ work: () throws -> T) rethrows -> (T, Double) {
        let start = Date()
        let value = try work()
        return (value, Date().timeIntervalSince(start))
    }

    static func run(large: Bool) -> Bool {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("decoylock-selftest-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pair = Pair(real: "correct horse", decoy: "nothing here")

        print("Decoy templates")
        for type in FileTypes.all {
            guard let decoy = Locker.decoyBody(for: type) else { check(false, "\(type.decoyResource) is in the bundle"); continue }
            check(type.isPlain(prefix: decoy.prefix(FileTypes.probeLength)) && type.looksComplete(decoy),
                  "\(type.decoyResource) looks like a normal .\(type.ext) (\(decoy.count) bytes)")
        }

        print("Format round trips")
        for type in FileTypes.all {
            let decoy = Locker.decoyBody(for: type) ?? Data()
            let body = sampleBody(for: type, size: 40_000)
            do {
                let locked = try LockedFormat.lock(body: body, name: "Budget.\(type.ext)", type: type, decoyBody: decoy,
                                                   realPassword: pair.real, decoyPassword: pair.decoy)
                let data = locked.data
                check(!type.isPlain(prefix: data.prefix(FileTypes.probeLength)), ".\(type.ext): locked bytes don't start like a normal file")
                check(LockedFormat.couldBeLocked(size: data.count), ".\(type.ext): even length, two equal halves")
                check(data.range(of: Data("Budget".utf8)) == nil, ".\(type.ext): file name isn't readable in the locked bytes")

                let (real, tReal) = time { LockedFormat.attempt(data, password: pair.real) }
                if case .real(let b, _) = real { check(b == body, ".\(type.ext): real password opens the real contents") }
                else { check(false, ".\(type.ext): real password opens the real contents") }

                let (fake, tDecoy) = time { LockedFormat.attempt(data, password: pair.decoy) }
                if case .decoy(let b, _) = fake { check(b == decoy, ".\(type.ext): decoy word opens the blank copy") }
                else { check(false, ".\(type.ext): decoy word opens the blank copy") }
                print(String(format: "        timing: real %.3fs, decoy %.3fs", tReal, tDecoy))

                for (pw, label) in [("wrong", "a wrong password"), ("", "an empty password"),
                                    (pair.real + " ", "the real password plus a trailing space"),
                                    (" " + pair.decoy, "the decoy word with a leading space")] {
                    if case .incorrect = LockedFormat.attempt(data, password: pw) { check(true, ".\(type.ext): \(label) is incorrect") }
                    else { check(false, ".\(type.ext): \(label) is incorrect") }
                }
            } catch {
                check(false, ".\(type.ext): lock threw \(error)")
            }
        }

        print("Passwords with spaces")
        do {
            let type = FileTypes.all[0]
            let decoy = Locker.decoyBody(for: type) ?? Data()
            let body = sampleBody(for: type, size: 1000)
            let locked = try LockedFormat.lock(body: body, name: "a.xlsx", type: type, decoyBody: decoy,
                                               realPassword: "secret ", decoyPassword: "decoy")
            if case .real = LockedFormat.attempt(locked.data, password: "secret ") { check(true, "\"secret \" opens a file locked with \"secret \"") }
            else { check(false, "\"secret \" opens a file locked with \"secret \"") }
            if case .incorrect = LockedFormat.attempt(locked.data, password: "secret") { check(true, "\"secret\" does not") }
            else { check(false, "\"secret\" does not") }
        } catch { check(false, "lock threw \(error)") }

        print("Editing and saving")
        do {
            let type = FileTypes.all[0]
            let decoy = Locker.decoyBody(for: type) ?? Data()
            let original = sampleBody(for: type, size: 30_000)
            let locked = try LockedFormat.lock(body: original, name: "Budget.xlsx", type: type, decoyBody: decoy,
                                               realPassword: pair.real, decoyPassword: pair.decoy)
            guard case .real(_, let keys) = LockedFormat.attempt(locked.data, password: pair.real) else {
                check(false, "open for editing"); return finish()
            }
            let halves = LockedFormat.split(locked.data)!
            let decoyBlobBefore = halves[1 - keys.realIndex]

            let small = sampleBody(for: type, size: 31_000)
            let resealed = try LockedFormat.reseal(current: locked.data, newBody: small, keys: keys)
            check(resealed.count == locked.data.count, "a small edit keeps the same file size")
            check(LockedFormat.split(resealed)![1 - keys.realIndex] == decoyBlobBefore, "the decoy blob is kept byte for byte")
            if case .real(let b, _) = LockedFormat.attempt(resealed, password: pair.real) { check(b == small, "the real password shows the edit") }
            else { check(false, "the real password shows the edit") }

            let big = sampleBody(for: type, size: 400_000)
            let grown = try LockedFormat.reseal(current: resealed, newBody: big, keys: keys)
            check(grown.count > resealed.count, "a big edit grows both halves")
            if case .real(let b, _) = LockedFormat.attempt(grown, password: pair.real) { check(b == big, "the real password shows the big edit") }
            else { check(false, "the real password shows the big edit") }
            if case .decoy(let b, _) = LockedFormat.attempt(grown, password: pair.decoy) { check(b == decoy, "the decoy word still shows the blank copy") }
            else { check(false, "the decoy word still shows the blank copy") }

            let other = try LockedFormat.lock(body: original, name: "Other.xlsx", type: type, decoyBody: decoy,
                                              realPassword: pair.real, decoyPassword: pair.decoy)
            check((try? LockedFormat.reseal(current: other.data, newBody: big, keys: keys)) == nil,
                  "refuses to write over a file that isn't the one it opened")
        } catch { check(false, "edit cycle threw \(error)") }

        print("Locking files in place")
        for type in FileTypes.all {
            let url = dir.appendingPathComponent("Budget.\(type.ext)")
            let body = sampleBody(for: type, size: 20_000)
            do {
                try body.write(to: url)
                let created = Date(timeIntervalSince1970: 1_600_000_000)
                let modified = Date(timeIntervalSince1970: 1_650_000_000)
                try FileManager.default.setAttributes([.creationDate: created, .modificationDate: modified], ofItemAtPath: url.path)
                setxattr(url.path, "com.decoylock.test", "tag", 3, 0, 0)
                let flag = "0083;6b006254;Safari;DB566A91-649F-4831-A0FC-EBFE3FBFE681"
                FileOps.Quarantine.write(flag, to: url)

                try Locker.lock(url, pair: pair, checkInUse: false, blankThumbnail: false)
                let dates = FileOps.dates(url)
                check(url.lastPathComponent == "Budget.\(type.ext)" && FileManager.default.fileExists(atPath: url.path), ".\(type.ext): same path and name")
                check(dates.created == created && dates.modified == modified, ".\(type.ext): creation and modification dates kept")
                check(getxattr(url.path, "com.decoylock.test", nil, 0, 0, 0) == 3, ".\(type.ext): extended attributes (tags) kept")
                check(OpenWith.isBound(url), ".\(type.ext): this file alone is set to open in Decoy Lock")
                check(FileOps.Quarantine.read(url) == nil, ".\(type.ext): the locked file has no quarantine flag, so macOS lets it open")
                if case .real(_, let keys) = LockedFormat.attempt(try Data(contentsOf: url), password: pair.real) {
                    check(keys.header.q == flag, ".\(type.ext): the flag is kept inside, for the unlocked copy")
                }
                if case .decoy(_, let header) = LockedFormat.attempt(try Data(contentsOf: url), password: pair.decoy) {
                    check(header.q == flag, ".\(type.ext): the blank copy gets the same flag")
                }
                let onDisk = try Data(contentsOf: url)
                if case .real(let b, _) = LockedFormat.attempt(onDisk, password: pair.real) { check(b == body, ".\(type.ext): opens with the real password") }
                else { check(false, ".\(type.ext): opens with the real password") }

                if case .alreadyLocked = Locker.problem(with: url, checkInUse: false) { check(true, ".\(type.ext): locking twice is refused") }
                else { check(false, ".\(type.ext): locking twice is refused") }
                FileOps.Quarantine.write(flag, to: url)
                removexattr(url.path, OpenWith.attribute, 0)
                check(Locker.repair(url) && FileOps.Quarantine.read(url) == nil && OpenWith.isBound(url),
                      ".\(type.ext): repairing clears the flag and points it back at Decoy Lock")
                let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.filter { $0.hasSuffix(".tmp") } ?? []
                check(leftovers.isEmpty, ".\(type.ext): no temp files left next to it")
            } catch {
                check(false, ".\(type.ext): \(error.localizedDescription)")
            }
        }
        let junk = dir.appendingPathComponent("Broken.xlsx")
        try? Data("not a spreadsheet".utf8).write(to: junk)
        if case .notValid = Locker.problem(with: junk, checkInUse: false) { check(true, "a broken .xlsx is left alone") }
        else { check(false, "a broken .xlsx is left alone") }

        sessionTest(in: dir, pair: pair)

        if large {
            print("Large file (100 MB)")
            let type = FileTypes.all[3]
            let url = dir.appendingPathComponent("Big.pdf")
            let body = sampleBody(for: type, size: 100 * 1024 * 1024)
            do {
                try body.write(to: url)
                let (_, tLock) = try time { try Locker.lock(url, pair: pair, checkInUse: false, blankThumbnail: false) }
                let onDisk = try Data(contentsOf: url, options: .mappedIfSafe)
                let (outcome, tOpen) = time { LockedFormat.attempt(onDisk, password: pair.real) }
                let (_, tDecoy) = time { LockedFormat.attempt(onDisk, password: pair.decoy) }
                if case .real(let b, _) = outcome { check(b == body, "100 MB round trip") } else { check(false, "100 MB round trip") }
                print(String(format: "        lock %.2fs, open real %.2fs, open decoy %.2fs, locked size %d MB",
                             tLock, tOpen, tDecoy, onDisk.count / 1_048_576))
            } catch { check(false, "100 MB: \(error)") }
        }

        return finish()
    }

    /// Plays the part of an app editing the unlocked copy, without launching any app.
    private static func sessionTest(in dir: URL, pair: Pair) {
        print("Saving edits back (about 25 seconds)")
        let type = FileTypes.all[0]
        let url = dir.appendingPathComponent("Edited.xlsx")
        let decoy = Locker.decoyBody(for: type) ?? Data()
        // An app that won't be running, so cleanup falls back to "app isn't open".
        let app = URL(fileURLWithPath: "/System/Applications/Chess.app")
        let wait: (Double) -> Void = { Thread.sleep(forTimeInterval: $0) }
        let realBody: () -> Data? = {
            guard let d = try? Data(contentsOf: url), case .real(let b, _) = LockedFormat.attempt(d, password: pair.real) else { return nil }
            return b
        }
        do {
            try sampleBody(for: type, size: 5000).write(to: url)
            let created = Date(timeIntervalSince1970: 1_600_000_000)
            try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
            try Locker.lock(url, pair: pair, checkInUse: false, blankThumbnail: false)
            guard case .real(let body, let keys) = LockedFormat.attempt(try Data(contentsOf: url), password: pair.real) else {
                check(false, "open for editing"); return
            }
            let temp = try SessionManager.shared.begin(body: body, name: url.lastPathComponent, type: type,
                                                       keys: keys, original: url, app: app)
            check(temp.lastPathComponent == "Edited.xlsx", "the unlocked copy has the same name")
            let perms = (try? FileManager.default.attributesOfItem(atPath: temp.deletingLastPathComponent().path))?[.posixPermissions] as? Int
            check(perms == 0o700, "the copy's folder is private to you")

            // Save style 1: write a new file and rename it into place (Office does this).
            let edit1 = sampleBody(for: type, size: 8000)
            let side = temp.deletingLastPathComponent().appendingPathComponent("~save.tmp")
            try edit1.write(to: side)
            rename(side.path, temp.path)
            wait(2.5)
            check(realBody() == edit1, "a save-by-rename is locked back in")

            // Save style 2: overwrite in place.
            let edit2 = sampleBody(for: type, size: 300_000)
            try edit2.write(to: temp)
            wait(2.5)
            check(realBody() == edit2, "an in-place save is locked back in")
            check(FileOps.dates(url).created == created, "the locked file keeps its creation date")
            check(OpenWith.isBound(url), "the locked file still opens in Decoy Lock after saves")
            if case .decoy(let b, _) = LockedFormat.attempt(try Data(contentsOf: url), password: pair.decoy) {
                check(b == decoy, "the decoy word still opens the blank copy")
            } else { check(false, "the decoy word still opens the blank copy") }

            // Half-written save: no end-of-archive record yet. Must not be locked in.
            try Data(edit2.prefix(1000)).write(to: temp)
            wait(2.5)
            check(realBody() == edit2, "a half-written save is ignored")
            try edit2.write(to: temp)

            // Decoy copy: edits are thrown away.
            let decoyTemp = try SessionManager.shared.begin(body: decoy, name: url.lastPathComponent, type: type,
                                                            keys: nil, original: url, app: app)
            try sampleBody(for: type, size: 7000).write(to: decoyTemp)
            wait(2.5)
            check(realBody() == edit2, "edits to the decoy copy are never written back")

            print("        waiting for cleanup…")
            wait(16)
            check(!FileManager.default.fileExists(atPath: temp.path), "the real copy is deleted once its app lets go")
            check(!FileManager.default.fileExists(atPath: decoyTemp.path), "the decoy copy is deleted too")
        } catch {
            check(false, "session test threw \(error)")
        }
    }

    private static func finish() -> Bool {
        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        return failures == 0
    }

    /// Bytes that pass the type's signature and completeness checks.
    private static func sampleBody(for type: SupportedType, size: Int) -> Data {
        var d = Data()
        switch type.completeness {
        case .zipArchive:
            d.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
            d.append(LockedFormat.randomBytes(max(0, size - 26)))
            d.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
            d.append(Data(count: 18))
        case .pdfDocument:
            d.append(Data("%PDF-1.7\n".utf8))
            d.append(LockedFormat.randomBytes(max(0, size - 15)))
            d.append(Data("\n%%EOF".utf8))
        }
        return d
    }
}
