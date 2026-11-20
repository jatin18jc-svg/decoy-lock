import AppKit

// Build-time and test entry points, used by build.sh. None of them show UI.
let args = CommandLine.arguments

if let i = args.firstIndex(of: "--info-plist"), i + 1 < args.count {
    exit(BuildTools.writeInfoPlist(to: args[i + 1]) ? 0 : 1)
}
if let i = args.firstIndex(of: "--render-iconset"), i + 1 < args.count {
    _ = NSApplication.shared
    exit(MainActor.assumeIsolated { BuildTools.renderIconset(to: args[i + 1]) } ? 0 : 1)
}
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    exit(MainActor.assumeIsolated { Snapshots.run(to: args[i + 1]) } ? 0 : 1)
}
if args.contains("--selftest") {
    exit(SelfTest.run(large: args.contains("--large")) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
