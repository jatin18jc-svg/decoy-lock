import AppKit
import SwiftUI

enum BuildTools {
    static let bundleID = "com.decoylock.app"
    static let version = "1.0"
    static let author = "Jatin Chutani"

    /// Info.plist is generated from FileTypes.all, so a new type is one row in that table.
    static func writeInfoPlist(to path: String) -> Bool {
        let documentTypes: [[String: Any]] = FileTypes.all.map { type in
            [
                "CFBundleTypeName": type.kindName,
                "CFBundleTypeRole": "Viewer",
                "LSHandlerRank": "Alternate",
                "LSItemContentTypes": [type.uti],
                // No CFBundleTypeIconFile on purpose: Finder keeps showing the type's
                // usual document icon instead of one branded with this app.
            ]
        }
        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "DecoyLock",
            "CFBundleIdentifier": bundleID,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Decoy Lock",
            "CFBundleDisplayName": "Decoy Lock",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "1",
            "CFBundleIconFile": "AppIcon",
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
            "LSApplicationCategoryType": "public.app-category.utilities",
            "NSHighResolutionCapable": true,
            "NSHumanReadableCopyright": "Made by \(author). Free for personal use.",
            "CFBundleDocumentTypes": documentTypes,
            "NSServices": [[
                "NSMenuItem": ["default": "Lock with Decoy Lock"],
                "NSMessage": "lockFiles",
                "NSPortName": "Decoy Lock",
                "NSRequiredContext": [String: String](),
                "NSSendFileTypes": FileTypes.all.map(\.uti),
            ]],
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            FileHandle.standardError.write(Data("Info.plist: \(error)\n".utf8))
            return false
        }
    }

    /// Renders the app icon from the mascot, so the icon and the app's character match.
    @MainActor
    static func renderIconset(to dir: String) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, px) in sizes {
            let renderer = ImageRenderer(content: AppIconView().frame(width: 1024, height: 1024))
            renderer.scale = px / 1024
            guard let cg = renderer.cgImage else { return false }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { return false }
            do { try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")) } catch { return false }
        }
        return true
    }
}

/// Dusk-coloured plate, mascot peeking up from the bottom edge.
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x5A4F78)), Color(nsColor: NSColor(hex: 0x352E4A))],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            Mascot(mood: .idle, size: 560)
                .offset(y: 40)
        }
        .frame(width: 1024, height: 1024)
    }
}
