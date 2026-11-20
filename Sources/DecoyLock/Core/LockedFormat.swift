import CommonCrypto
import CryptoKit
import Foundation
import Security

/// A key plus the salt it was derived with (the salt is stored at the front of its blob).
struct BlobKey {
    let salt: Data
    let key: SymmetricKey
}

/// The JSON header at the start of each blob's plaintext.
///
/// `dk` is the trick that lets the app re-save edits without knowing the decoy word:
/// in the real blob it holds the decoy blob's key, and in the decoy blob it holds
/// 32 random bytes. Both headers have the same shape, so neither says which is which.
struct BlobHeader: Codable {
    var v: Int = 1
    var name: String
    var type: String
    var size: Int
    var dk: String
    /// The original file's quarantine flag ("downloaded from the internet"), if it had one.
    /// Kept in here instead of on the locked file: macOS refuses to hand a flagged file to an
    /// app that isn't notarized, but the unlocked copy should still carry it so apps like
    /// Office open downloads in Protected View. Absent in files locked by older builds.
    var q: String?
}

/// Everything needed to write edits back into a locked file, held in memory only.
struct RealSessionKeys {
    let realIndex: Int
    let realKey: BlobKey
    let decoyKey: BlobKey
    let header: BlobHeader
}

enum OpenOutcome {
    case real(body: Data, keys: RealSessionKeys)
    case decoy(body: Data, header: BlobHeader)
    case incorrect
}

enum FormatError: LocalizedError {
    case notLocked
    case changedOnDisk
    case sealFailed

    var errorDescription: String? {
        switch self {
        case .notLocked: return "The file isn't locked."
        case .changedOnDisk: return "The locked file was changed or replaced while it was open."
        case .sealFailed: return "Encryption failed."
        }
    }
}

/// Locked file layout:
///
///     [blob A][blob B]                       order picked at random when locking
///     blob = salt (16) | nonce (12) | AES-GCM ciphertext | tag (16)
///     plaintext = u32 LE header length | JSON header | file bytes | random padding
///
/// Both blobs are padded to the same length, so each is exactly half the file.
/// There is no magic number or marker anywhere.
enum LockedFormat {
    static let saltLength = 16
    static let nonceLength = 12
    static let tagLength = 16
    static let iterations: UInt32 = 310_000
    static var overhead: Int { saltLength + nonceLength + tagLength }
    /// Small files are padded up to this so a 3 KB file and a 40 KB file look alike.
    static let minimumPlaintext = 64 * 1024

    // MARK: Primitives

    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        guard count > 0 else { return data }
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "System random number generator failed")
        return data
    }

    /// PBKDF2-HMAC-SHA256. The password is NFC-normalised but otherwise used exactly
    /// as typed, so a trailing space is part of it.
    static func deriveKey(_ password: String, salt: Data) -> SymmetricKey {
        var pw = Array(password.precomposedStringWithCanonicalMapping.utf8)
        // An empty password still costs a full derivation so it can't be spotted by timing.
        // Callers reject empty passwords before looking at the result.
        if pw.isEmpty { pw = [0] }
        var out = [UInt8](repeating: 0, count: 32)
        let status = pw.withUnsafeBufferPointer { pwp in
            salt.withUnsafeBytes { sp in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    UnsafeRawPointer(pwp.baseAddress!).assumingMemoryBound(to: CChar.self), pwp.count,
                    sp.bindMemory(to: UInt8.self).baseAddress!, sp.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                    &out, out.count)
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed")
        return SymmetricKey(data: out)
    }

    static func makeKey(_ password: String) -> BlobKey {
        let salt = randomBytes(saltLength)
        return BlobKey(salt: salt, key: deriveKey(password, salt: salt))
    }

    static func rawKey(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    /// Rounds up in steps of about 12%, so file size only hints at a rough range.
    static func paddedSize(for n: Int) -> Int {
        if n <= minimumPlaintext { return minimumPlaintext }
        let log2 = Int.bitWidth - n.leadingZeroBitCount - 1
        let step = max(4096, 1 << max(0, log2 - 3))
        return ((n + step - 1) / step) * step
    }

    static func couldBeLocked(size: Int) -> Bool {
        size % 2 == 0 && size / 2 >= overhead + 8
    }

    static func split(_ data: Data) -> [Data]? {
        guard couldBeLocked(size: data.count) else { return nil }
        let half = data.count / 2
        let base = data.startIndex
        return [data.subdata(in: base..<(base + half)), data.subdata(in: (base + half)..<(base + 2 * half))]
    }

    static func plaintext(header json: Data, body: Data, size: Int) -> Data {
        var p = Data(capacity: size)
        let n = UInt32(json.count)
        p.append(contentsOf: [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)])
        p.append(json)
        p.append(body)
        if p.count < size { p.append(randomBytes(size - p.count)) }
        return p
    }

    static func parse(_ plain: Data) -> (header: BlobHeader, body: Data)? {
        let p = plain.startIndex
        guard plain.count >= 4 else { return nil }
        let len = Int(UInt32(plain[p]) | UInt32(plain[p + 1]) << 8 | UInt32(plain[p + 2]) << 16 | UInt32(plain[p + 3]) << 24)
        guard len > 0, 4 + len <= plain.count,
              let header = try? JSONDecoder().decode(BlobHeader.self, from: plain.subdata(in: (p + 4)..<(p + 4 + len))),
              header.size >= 0, 4 + len + header.size <= plain.count
        else { return nil }
        let start = p + 4 + len
        return (header, plain.subdata(in: start..<(start + header.size)))
    }

    static func seal(_ plain: Data, with k: BlobKey) throws -> Data {
        let box = try AES.GCM.seal(plain, using: k.key)
        guard let combined = box.combined else { throw FormatError.sealFailed }
        return k.salt + combined
    }

    static func openBlob(_ blob: Data, key: SymmetricKey) -> Data? {
        guard blob.count > overhead else { return nil }
        let combined = blob.subdata(in: (blob.startIndex + saltLength)..<blob.endIndex)
        guard let box = try? AES.GCM.SealedBox(combined: combined) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    // MARK: Locking

    struct Locked {
        let data: Data
        let keys: RealSessionKeys
    }

    static func lock(body: Data, name: String, type: SupportedType, decoyBody: Data,
                     realPassword: String, decoyPassword: String, quarantine: String? = nil) throws -> Locked {
        precondition(!realPassword.isEmpty && !decoyPassword.isEmpty && realPassword != decoyPassword)
        while true {
            let realKey = makeKey(realPassword)
            let decoyKey = makeKey(decoyPassword)
            let header = BlobHeader(name: name, type: type.ext, size: body.count,
                                    dk: rawKey(decoyKey.key).base64EncodedString(), q: quarantine)
            let keys = RealSessionKeys(realIndex: Int.random(in: 0...1), realKey: realKey, decoyKey: decoyKey, header: header)
            let data = try assemble(realBody: body, decoyBody: decoyBody, keys: keys, keepDecoyBlob: nil)
            // Random bytes that happen to start like a real file would be passed straight
            // through unopened. The odds are about 1 in 4 billion; reroll if it happens.
            if !type.isPlain(prefix: data.prefix(FileTypes.probeLength)) {
                return Locked(data: data, keys: keys)
            }
        }
    }

    static func assemble(realBody: Data, decoyBody: Data, keys: RealSessionKeys, keepDecoyBlob: Data?) throws -> Data {
        let encoder = JSONEncoder()
        var realHeader = keys.header
        realHeader.size = realBody.count
        let decoyHeader = BlobHeader(name: realHeader.name, type: realHeader.type, size: decoyBody.count,
                                     dk: randomBytes(32).base64EncodedString(), q: realHeader.q)
        let realJSON = try encoder.encode(realHeader)
        let decoyJSON = try encoder.encode(decoyHeader)
        let size = paddedSize(for: max(4 + realJSON.count + realBody.count, 4 + decoyJSON.count + decoyBody.count))

        let realBlob = try seal(plaintext(header: realJSON, body: realBody, size: size), with: keys.realKey)
        let decoyBlob: Data
        if let keep = keepDecoyBlob, keep.count == size + overhead {
            decoyBlob = keep
        } else {
            decoyBlob = try seal(plaintext(header: decoyJSON, body: decoyBody, size: size), with: keys.decoyKey)
        }
        return keys.realIndex == 0 ? realBlob + decoyBlob : decoyBlob + realBlob
    }

    /// Checks a freshly locked file with the keys that made it, before the original is replaced.
    static func verify(_ locked: Locked, realBody: Data, decoyBody: Data) -> Bool {
        guard let halves = split(locked.data),
              let real = openBlob(halves[locked.keys.realIndex], key: locked.keys.realKey.key).flatMap(parse),
              let decoy = openBlob(halves[1 - locked.keys.realIndex], key: locked.keys.decoyKey.key).flatMap(parse)
        else { return false }
        return real.body == realBody && decoy.body == decoyBody
    }

    // MARK: Opening

    /// Tries a password against both blobs. Every attempt does the same work in the
    /// same order (two derivations, two decrypts, one check of the other blob),
    /// so the real password and the decoy word take the same time.
    static func attempt(_ data: Data, password: String) -> OpenOutcome {
        guard let halves = split(data) else { return .incorrect }
        var keys: [BlobKey] = []
        var plains: [Data?] = []
        for half in halves {
            let salt = Data(half.prefix(saltLength))
            let k = BlobKey(salt: salt, key: deriveKey(password, salt: salt))
            keys.append(k)
            plains.append(openBlob(half, key: k.key))
        }
        guard !password.isEmpty,
              let idx = plains.firstIndex(where: { $0 != nil }),
              let (header, body) = plains[idx].flatMap(parse)
        else { return .incorrect }

        let other = 1 - idx
        let dk = Data(base64Encoded: header.dk).flatMap { $0.count == 32 ? SymmetricKey(data: $0) : nil }
        // Always try the other blob, whichever password this is.
        let otherPlain = openBlob(halves[other], key: dk ?? SymmetricKey(size: .bits256))
        if let dk, let otherPlain, parse(otherPlain) != nil {
            let decoyKey = BlobKey(salt: Data(halves[other].prefix(saltLength)), key: dk)
            return .real(body: body, keys: RealSessionKeys(realIndex: idx, realKey: keys[idx], decoyKey: decoyKey, header: header))
        }
        return .decoy(body: body, header: header)
    }

    // MARK: Saving edits

    /// Re-encrypts edited contents into the locked file. The decoy blob is kept
    /// byte-for-byte when the padded size doesn't change, and re-padded (same key,
    /// same salt, new nonce) when it does.
    static func reseal(current: Data, newBody: Data, keys: RealSessionKeys) throws -> Data {
        guard let halves = split(current) else { throw FormatError.changedOnDisk }
        let decoyBlob = halves[1 - keys.realIndex]
        guard Data(decoyBlob.prefix(saltLength)) == keys.decoyKey.salt,
              let (_, decoyBody) = openBlob(decoyBlob, key: keys.decoyKey.key).flatMap(parse)
        else { throw FormatError.changedOnDisk }
        return try assemble(realBody: newBody, decoyBody: decoyBody, keys: keys, keepDecoyBlob: decoyBlob)
    }
}
