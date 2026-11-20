import AppKit
import SwiftUI

final class LockModel: ObservableObject {
    struct Item: Identifiable {
        let url: URL
        var problem: String?
        /// Not a problem: something Decoy Lock fixed or wants you to know.
        var note: String?
        var locked = false
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }
    enum Phase { case ready, working, finished }

    @Published var items: [Item]
    @Published var phase: Phase = .ready
    @Published var differentPair = false
    @Published var real = ""
    @Published var confirm = ""
    @Published var decoy = ""
    @Published var revealed = false
    @Published var remember = true
    @Published var pairProblem: String?
    let hasSavedPair = PairStore.exists

    init(urls: [URL]) {
        items = urls.map { url in
            let problem = Locker.problem(with: url)
            if case .alreadyLocked(let name) = problem {
                let fixed = Locker.repair(url)
                return Item(url: url, note: fixed
                    ? "\(name) is already locked. It was set to open somewhere else, or flagged as downloaded; it now opens in Decoy Lock again."
                    : "\(name) is already locked.")
            }
            return Item(url: url, problem: problem?.errorDescription)
        }
    }

    var lockable: [Item] { items.filter { $0.problem == nil && $0.note == nil } }
    var needsPair: Bool { !hasSavedPair || differentPair }
    var lockedCount: Int { items.filter(\.locked).count }
}

struct LockView: View {
    @StateObject var model: LockModel
    @FocusState private var focus: PairField?
    var close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Mascot(mood: currentMood, size: 92)
                .frame(width: 92)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(Fonts.display(21))
                    .fixedSize(horizontal: false, vertical: true)
                fileList

                if model.phase == .finished {
                    Text(finishedMessage)
                        .font(Fonts.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !model.lockable.isEmpty {
                    pairSection
                }

                HStack {
                    Spacer()
                    if model.phase == .finished || model.lockable.isEmpty {
                        Button("Done", action: close).actionButton().keyboardShortcut(.defaultAction)
                    } else {
                        Button("Cancel", action: close).controlSize(.large).keyboardShortcut(.cancelAction)
                        Button(model.phase == .working ? "Locking…" : lockButtonTitle, action: lock)
                            .actionButton()
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.phase == .working)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 20)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var currentMood: Mood {
        switch model.phase {
        case .working: return .covering
        case .finished: return model.lockedCount > 0 ? .happy : .worried
        case .ready:
            if model.lockable.isEmpty { return model.items.allSatisfy({ $0.note != nil }) ? .happy : .worried }
            return model.needsPair ? mood(for: focus, revealed: model.revealed) : .idle
        }
    }

    private var title: String {
        switch model.phase {
        case .finished:
            return model.lockedCount == 0 ? "Nothing was locked." : "Locked."
        default:
            if model.lockable.isEmpty {
                if model.items.allSatisfy({ $0.note != nil }) { return model.items.count == 1 ? "Already locked." : "All already locked." }
                return model.items.count == 1 ? "This one can't be locked." : "These can't be locked."
            }
            return model.lockable.count == 1 ? "Lock \(model.lockable[0].name)?" : "Lock \(model.lockable.count) files?"
        }
    }

    private var lockButtonTitle: String {
        model.lockable.count == 1 ? "Lock File" : "Lock \(model.lockable.count) Files"
    }

    private var finishedMessage: String {
        let n = model.lockedCount
        if n == 0 { return "Have a look at the notes above, then try again." }
        let subject = n == 1 ? model.items.first(where: \.locked)!.name : "\(n) files"
        let verb = n == 1 ? "keeps its" : "keep their"
        return "\(subject) \(verb) name, icon and app. Open with your real password to see everything, or your decoy word to see a blank copy."
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.items.prefix(5)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 18, height: 18)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        if let problem = item.problem {
                            Text(problem).font(Fonts.small).foregroundStyle(Palette.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let note = item.note {
                            Text(note).font(Fonts.small).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    if item.locked {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.moss)
                    }
                }
            }
            if model.items.count > 5 {
                Text("and \(model.items.count - 5) more").font(Fonts.small).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var pairSection: some View {
        if model.hasSavedPair {
            Toggle("Use a different pair for \(model.lockable.count == 1 ? "this file" : "these files")", isOn: $model.differentPair)
                .toggleStyle(.checkbox)
                .font(Fonts.body)
                .disabled(model.phase == .working)
            if !model.differentPair {
                Text("Locks with your usual real password and decoy word.")
                    .font(Fonts.small)
                    .foregroundStyle(.secondary)
            }
        }
        if model.needsPair {
            PairFields(real: $model.real, confirm: $model.confirm, decoy: $model.decoy,
                       revealed: $model.revealed, focus: $focus)
                .disabled(model.phase == .working)
            if !model.hasSavedPair {
                Toggle("Remember this pair for next time", isOn: $model.remember)
                    .toggleStyle(.checkbox)
                    .font(Fonts.body)
            } else {
                Text("Write this pair down somewhere safe. Decoy Lock won't remember it, so if you forget it, nothing can open these files.")
                    .font(Fonts.small)
                    .foregroundStyle(.secondary)
            }
            if let problem = model.pairProblem {
                Text(problem).font(Fonts.small).foregroundStyle(Palette.warning)
            } else if let note = PairRules.note(real: model.real, decoy: model.decoy) {
                Text(note).font(Fonts.small).foregroundStyle(.secondary)
            }
        }
    }

    private func lock() {
        let pair: Pair
        if model.needsPair {
            if let problem = PairRules.problem(real: model.real, confirm: model.confirm, decoy: model.decoy) {
                model.pairProblem = problem
                return
            }
            pair = Pair(real: model.real, decoy: model.decoy)
            if !model.hasSavedPair && model.remember {
                do { try PairStore.save(pair) } catch {
                    model.pairProblem = error.localizedDescription
                    return
                }
            }
        } else {
            guard let saved = PairStore.load() else {
                model.pairProblem = "Decoy Lock couldn't read your usual pair from the Keychain."
                model.differentPair = true
                return
            }
            pair = saved
        }

        model.pairProblem = nil
        focus = nil
        model.phase = .working
        let targets = model.lockable.map(\.url)
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [URL: String?] = [:]
            for url in targets {
                do {
                    try Locker.lock(url, pair: pair)
                    results[url] = .some(nil)
                } catch {
                    results[url] = .some(error.localizedDescription)
                }
            }
            DispatchQueue.main.async {
                for i in model.items.indices {
                    guard let result = results[model.items[i].url] else { continue }
                    if let message = result { model.items[i].problem = message } else { model.items[i].locked = true }
                }
                model.real = ""; model.confirm = ""; model.decoy = ""
                model.phase = .finished
            }
        }
    }
}
