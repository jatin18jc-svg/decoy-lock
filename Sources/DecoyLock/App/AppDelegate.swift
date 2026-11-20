import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var receivedFiles = false
    private var launchedByUser = false
    private var launchReasonKnown = false
    private var readyForFirstWindow = false
    private var firstWindowDecided = false
    private var prefsObserver: AnyCancellable?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        // Work out why we were launched: to open files, at login, or by the user.
        // A plain launch arrives as an "open application" event, flagged when it's a
        // login item. A launch to open files arrives as "open documents" instead.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleOpenApplication(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenApplication))
    }

    @objc private func handleOpenApplication(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        let isLoginItem = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        launchedByUser = !isLoginItem
        launchReasonKnown = true
        decideFirstWindow()
    }

    /// Runs once both have happened: launching settled (so file opens have arrived)
    /// and the launch reason is known. They can arrive in either order.
    private func decideFirstWindow() {
        guard readyForFirstWindow, !firstWindowDecided, !receivedFiles else { return }
        if !Prefs.onboardingDone {
            firstWindowDecided = true
            Windows.showOnboarding()
            return
        }
        guard launchReasonKnown else { return }
        firstWindowDecided = true
        if launchedByUser { Windows.showSettings() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()
        SessionManager.shared.cleanUpLeftovers()
        applyMenuBarPreference()
        prefsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyMenuBarPreference() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            readyForFirstWindow = true
            decideFirstWindow()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFiles = true
        urls.forEach(Opener.open)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Prefs.onboardingDone { Windows.showSettings() } else { Windows.showOnboarding() }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        SessionManager.shared.flushAll()
    }

    private func applyMenuBarPreference() {
        if Prefs.showMenuBarIcon, statusItem == nil {
            statusItem = StatusItemController()
        } else if !Prefs.showMenuBarIcon, let item = statusItem {
            item.remove()
            statusItem = nil
        }
    }

    @objc func showSettings(_ sender: Any?) { Windows.showSettings() }

    /// Quitting while a real file is open means later saves won't be locked back in.
    static func confirmQuit() {
        let open = SessionManager.shared.activeRealCount
        if open > 0 {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = open == 1 ? "A locked file is still open." : "\(open) locked files are still open."
            alert.informativeText = "Changes you save after quitting won't be locked back in. Close the file first, or quit anyway. Decoy Lock opens again the next time you open a locked file."
            alert.addButton(withTitle: "Quit Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        NSApp.terminate(nil)
    }

    @objc func quitApp(_ sender: Any?) { AppDelegate.confirmQuit() }
}

/// "Lock with Decoy Lock" in Finder's right-click menu (Services, or Quick Actions on some versions).
final class ServiceProvider: NSObject {
    @objc func lockFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files were selected." as NSString
            return
        }
        DispatchQueue.main.async { Windows.showLock(urls) }
    }
}

/// A background app has no visible menu bar, but text fields still need Edit
/// shortcuts (paste into a password field) and windows need Close.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Decoy Lock", action: #selector(AppDelegate.quitApp(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}
