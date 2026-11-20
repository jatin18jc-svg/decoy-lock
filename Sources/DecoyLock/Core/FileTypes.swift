import Foundation
import UniformTypeIdentifiers

/// A byte pattern that marks a normal, unlocked file.
struct Signature {
    let bytes: [UInt8]
    /// How far into the file the pattern may start. 0 means it must be at the very start.
    let window: Int

    func matches(_ prefix: Data) -> Bool {
        let p = [UInt8](prefix)
        guard !bytes.isEmpty, p.count >= bytes.count else { return false }
        let last = min(window, p.count - bytes.count)
        for i in 0...last where p[i] == bytes[0] {
            if Array(p[i..<(i + bytes.count)]) == bytes { return true }
        }
        return false
    }
}

/// How to tell that an app has finished writing a save (so we never lock in half a file).
enum CompletenessCheck {
    case zipArchive
    case pdfDocument
}

struct SupportedType: Identifiable {
    let ext: String
    let uti: String
    /// What the setup screen calls these files.
    let label: String
    /// Matches Finder's kind string so Get Info reads the same as before.
    let kindName: String
    let signatures: [Signature]
    let decoyResource: String
    let completeness: CompletenessCheck
    /// Fallback apps to hand files to, best first, if no default was recorded.
    let preferredApps: [String]

    var id: String { uti }
    var utType: UTType { UTType(uti) ?? .data }

    func isPlain(prefix: Data) -> Bool {
        signatures.contains { $0.matches(prefix) }
    }

    /// True when the bytes look like a whole file of this type, not one caught mid-write.
    func looksComplete(_ data: Data) -> Bool {
        if FileTypes.officeEncrypted.matches(data.prefix(16)) { return true }
        switch completeness {
        case .zipArchive:
            // End-of-central-directory record sits in the last 22 bytes plus any comment (max 64 KB).
            let tail = data.suffix(min(data.count, 65_557))
            return tail.range(of: Data([0x50, 0x4B, 0x05, 0x06])) != nil
        case .pdfDocument:
            return data.suffix(min(data.count, 2048)).range(of: Data("%%EOF".utf8)) != nil
        }
    }
}

/// The one table to edit when adding a file type. Each new row also needs an
/// entry in Info.plist (CFBundleDocumentTypes and NSSendFileTypes) and a decoy
/// file in Resources/Decoys.
enum FileTypes {
    static let zip = Signature(bytes: [0x50, 0x4B, 0x03, 0x04], window: 0)
    /// Office files protected with Office's own password use the older compound-file container.
    static let officeEncrypted = Signature(bytes: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], window: 0)
    static let pdf = Signature(bytes: Array("%PDF-".utf8), window: 1024)

    static let all: [SupportedType] = [
        SupportedType(
            ext: "xlsx", uti: "org.openxmlformats.spreadsheetml.sheet",
            label: "Spreadsheets", kindName: "Microsoft Excel Workbook (.xlsx)",
            signatures: [zip, officeEncrypted], decoyResource: "empty.xlsx",
            completeness: .zipArchive,
            preferredApps: ["com.microsoft.Excel", "com.apple.iWork.Numbers"]),
        SupportedType(
            ext: "docx", uti: "org.openxmlformats.wordprocessingml.document",
            label: "Documents", kindName: "Microsoft Word document (.docx)",
            signatures: [zip, officeEncrypted], decoyResource: "empty.docx",
            completeness: .zipArchive,
            preferredApps: ["com.microsoft.Word", "com.apple.iWork.Pages", "com.apple.TextEdit"]),
        SupportedType(
            ext: "pptx", uti: "org.openxmlformats.presentationml.presentation",
            label: "Presentations", kindName: "Microsoft PowerPoint Presentation",
            signatures: [zip, officeEncrypted], decoyResource: "empty.pptx",
            completeness: .zipArchive,
            preferredApps: ["com.microsoft.Powerpoint", "com.apple.iWork.Keynote"]),
        SupportedType(
            ext: "pdf", uti: "com.adobe.pdf",
            label: "PDFs", kindName: "PDF document",
            signatures: [pdf], decoyResource: "empty.pdf",
            completeness: .pdfDocument,
            preferredApps: ["com.apple.Preview"]),
    ]

    /// Enough bytes to check every signature in the table.
    static var probeLength: Int {
        all.flatMap(\.signatures).map { $0.window + $0.bytes.count }.max() ?? 64
    }

    static func type(for url: URL) -> SupportedType? {
        let ext = url.pathExtension.lowercased()
        return all.first { $0.ext == ext }
    }

    static var extensionList: String {
        let exts = all.map { ".\($0.ext)" }
        guard exts.count > 1 else { return exts.first ?? "" }
        return exts.dropLast().joined(separator: ", ") + " or " + exts.last!
    }
}
