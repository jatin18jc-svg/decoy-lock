import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var hasPair = PairStore.exists
    @Published var isOpener = DefaultApps.shared.isOpenerForAny
    @Published var openerBusy = false
    @Published var openerMessage: String?
    @Published var openAtLogin = LoginItem.isOn
    @Published var refresh = 0

    func reload() {
        hasPair = PairStore.exists
        isOpener = DefaultApps.shared.isOpenerForAny
        openAtLogin = LoginItem.isOn
        refresh += 1
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(PrefKey.blankThumbnails) private var blankThumbnails = false
    @ViewState private var changingPair = false
    @ViewState private var shownPairs: [Pair] = []
    @ViewState private var hoveringUninstall = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section("Your pair") {
                    LabeledContent {
                        HStack {
                            if model.hasPair {
                                Button("Show Pair…") { showPair() }
                            }
                            Button(model.hasPair ? "Change Pair…" : "Set Pair…") { changingPair = true }
                        }
                    } label: {
                        Text("Usual pair")
                        Text(model.hasPair ? "Saved in your Keychain" : "Not set yet")
                    }
                    Text("Forgot it? Show Pair displays your pair, and any earlier ones, after Touch ID or your Mac password. A new pair only applies to files you lock from now on.")
                        .font(Fonts.small)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(FileTypes.all) { type in
                        TypeRow(type: type)
                            .padding(.horizontal, -10)
                    }
                    .id(model.refresh)
                    if model.isOpener {
                        HStack {
                            Text("Decoy Lock is set to open every file of some of these types. Locked files don't need that.")
                                .font(Fonts.small)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Give Them Back") { restore() }.disabled(model.openerBusy)
                        }
                    }
                    if let message = model.openerMessage {
                        Text(message).font(Fonts.small).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Opening files")
                } footer: {
                    Text("Only files you lock open through Decoy Lock. Everything else opens in its usual app, as before. If a locked file ever opens as damaged, right-click it and choose Open With > Decoy Lock.")
                        .font(Fonts.small)
                        .foregroundStyle(.secondary)
                }

                Section("Looks") {
                    Toggle("Show the menu bar icon", isOn: $showMenuBarIcon)
                    Toggle(isOn: $blankThumbnails) {
                        Text("Give locked files a blank-page thumbnail")
                        Text("Finder shows a preview for normal files and a plain icon for locked ones. This gives newly locked files the preview of an empty page instead.")
                    }
                }

                Section("Startup") {
                    Toggle(isOn: Binding(get: { model.openAtLogin }, set: { on in
                        LoginItem.set(on)
                        model.openAtLogin = LoginItem.isOn
                    })) {
                        Text("Open Decoy Lock when I log in")
                        Text("Keeps opening fast and cleans up spare copies after a restart.")
                    }
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Uninstall")
                            Text("Forgets your pairs and removes the app. Locked files stay locked.")
                                .font(Fonts.small)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Uninstall Decoy Lock…", role: .destructive) { Uninstaller.confirm() }
                            .onHover { hoveringUninstall = $0 }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 640)
        .sheet(isPresented: $changingPair, onDismiss: model.reload) {
            ChangePairSheet(hasPair: model.hasPair) { changingPair = false }
        }
        .sheet(isPresented: Binding(get: { !shownPairs.isEmpty }, set: { if !$0 { shownPairs = [] } })) {
            ShowPairSheet(pairs: shownPairs) { shownPairs = [] }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Mascot(mood: hoveringUninstall ? .worried : .idle, size: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text("Decoy Lock").font(Fonts.display(20)).foregroundStyle(Palette.ink)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"), made by \(BuildTools.author)")
                    .font(Fonts.small)
                    .foregroundStyle(Palette.dusk)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Palette.fur.ignoresSafeArea())
        .overlay(alignment: .bottom) { Palette.furDeep.frame(height: 1) }
    }

    private func showPair() {
        OwnerCheck.confirm("show your Decoy Lock passwords") { ok in
            guard ok, let pair = PairStore.load() else { return }
            shownPairs = [pair] + PairStore.earlierPairs()
        }
    }

    private func restore() {
        model.openerBusy = true
        Task { @MainActor in
            let failures = await DefaultApps.shared.restore()
            model.openerMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
            model.openerBusy = false
            model.reload()
        }
    }
}

struct ChangePairSheet: View {
    let hasPair: Bool
    var done: () -> Void

    @ViewState private var current = ""
    @ViewState private var real = ""
    @ViewState private var confirm = ""
    @ViewState private var decoy = ""
    @ViewState private var revealed = false
    @ViewState private var problem: String?
    @ViewState private var confirmedOwner = false
    @FocusState private var focus: PairField?

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Mascot(mood: mood(for: focus, revealed: revealed), size: 84)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 14) {
                Text(hasPair ? "Change your pair" : "Set your pair").font(Fonts.display(20))
                if hasPair && !confirmedOwner {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current real password").font(.system(size: 12, weight: .semibold))
                        SecretField(title: "So nobody else can swap it", text: $current, revealed: revealed, field: .current, focus: $focus)
                        Button("Forgot it? Use Touch ID or your Mac password") {
                            OwnerCheck.confirm("change your Decoy Lock pair") { ok in
                                if ok { confirmedOwner = true; problem = nil; focus = .real }
                            }
                        }
                        .buttonStyle(.link)
                        .font(Fonts.small)
                    }
                }
                PairFields(real: $real, confirm: $confirm, decoy: $decoy, revealed: $revealed, focus: $focus)
                if let problem {
                    Text(problem).font(Fonts.small).foregroundStyle(Palette.warning)
                } else if let note = PairRules.note(real: real, decoy: decoy) {
                    Text(note).font(Fonts.small).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: done).controlSize(.large).keyboardShortcut(.cancelAction)
                    Button("Save Pair", action: save).actionButton().keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 470)
        .onAppear { focus = hasPair ? .current : .real }
    }

    private func save() {
        if hasPair && !confirmedOwner {
            guard let saved = PairStore.load() else {
                problem = "Decoy Lock couldn't read your current pair from the Keychain."
                return
            }
            guard saved.real == current else {
                problem = "That isn't your current real password."
                return
            }
        }
        if let p = PairRules.problem(real: real, confirm: confirm, decoy: decoy) {
            problem = p
            return
        }
        do {
            try PairStore.save(Pair(real: real, decoy: decoy))
            done()
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Shown only after Touch ID or the Mac password.
struct ShowPairSheet: View {
    let pairs: [Pair]
    var done: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Mascot(mood: .peeking, size: 84)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 14) {
                Text("Your pair").font(Fonts.display(20))
                pairBlock(pairs[0])
                if pairs.count > 1 {
                    Divider()
                    Text("Earlier pairs, for files you locked before changing it")
                        .font(.system(size: 12, weight: .semibold))
                    let earlier = VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(pairs.dropFirst().enumerated()), id: \.offset) { _, pair in pairBlock(pair) }
                    }
                    // A scroll view in a sheet that sizes to fit gets no height, so only
                    // scroll (at a fixed height) once the list is long.
                    if pairs.count > 4 {
                        ScrollView { earlier.frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 160)
                    } else {
                        earlier
                    }
                }
                Text("Files you locked with a one-off pair aren't listed here. Nothing can open those without that pair.")
                    .font(Fonts.small)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Done", action: done).actionButton().keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func pairBlock(_ pair: Pair) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Real password").foregroundStyle(.secondary)
                Text(visible(pair.real)).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
            }
            GridRow {
                Text("Decoy word").foregroundStyle(.secondary)
                Text(visible(pair.decoy)).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
            }
        }
        .font(Fonts.body)
    }

    /// Makes leading and trailing spaces visible, since they're part of the password.
    private func visible(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed != s else { return s }
        return s.replacingOccurrences(of: " ", with: "␣")
    }
}

enum Uninstaller {
    static func confirm() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall Decoy Lock?"
        alert.informativeText = """
        Your files stay locked. Without Decoy Lock they look damaged and won't open, so first open anything you want to keep unlocked and use File > Save As in its app.

        Decoy Lock will delete your saved pairs from the Keychain, so Show Pair can't help you recover them afterwards. Write them down first if you might need them. It will also stop opening at login and move itself to the Trash.
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task { @MainActor in
            let failures = await DefaultApps.shared.restore()
            LoginItem.set(false)
            PairStore.delete()
            Prefs.reset()
            SessionManager.shared.flushAll()
            if !failures.isEmpty {
                Alerts.show(title: "Some file types didn't switch back",
                            message: failures.joined(separator: "\n") + "\n\nSet them by hand: select a file, choose File > Get Info, pick an app under Open With, then click Change All.")
            }
            NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
}
