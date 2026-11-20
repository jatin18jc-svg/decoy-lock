import AppKit
import SwiftUI

final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case meet, pair, done
    }
    enum Demo: String, CaseIterable, Identifiable {
        case real = "Real password"
        case decoy = "Decoy word"
        case wrong = "Wrong guess"
        var id: String { rawValue }
    }

    @Published var step: Step = .meet
    @Published var demo: Demo = .real
    @Published var real = ""
    @Published var confirm = ""
    @Published var decoy = ""
    @Published var revealed = false
    @Published var pairProblem: String?
    @Published var wrongShakes: CGFloat = 0
    let hadPair = PairStore.exists
}

struct OnboardingView: View {
    @StateObject private var model = OnboardingModel()
    @FocusState private var focus: PairField?
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true
    @ViewState private var openAtLogin = true
    var close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Stage {
                VStack {
                    Spacer()
                    Mascot(mood: stageMood, size: 148)
                    Spacer()
                    StepDots(current: model.step.rawValue, count: OnboardingModel.Step.allCases.count)
                        .padding(.bottom, 26)
                }
            }
            .frame(width: 228)

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch model.step {
                    case .meet: meet
                    case .pair: pair
                    case .done: done
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 30)
            .padding(.top, 46)
            .padding(.bottom, 24)
            .frame(width: 452)
        }
        .frame(height: 496)
        .onAppear { openAtLogin = LoginItem.isOn || !Prefs.onboardingDone }
    }

    private var stageMood: Mood {
        switch model.step {
        case .meet:
            switch model.demo {
            case .real: return .happy
            case .decoy: return .possum
            case .wrong: return .worried
            }
        case .pair: return mood(for: focus, revealed: model.revealed)
        case .done: return .happy
        }
    }

    // MARK: Steps

    private var meet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("One file, two passwords.").font(Fonts.display(26))
            Text("Lock a file and it keeps its name, its icon and its app. Your real password opens it. Your decoy word opens a blank copy instead, so the file plays possum.")
                .font(Fonts.body)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Try typing", selection: $model.demo) {
                ForEach(OnboardingModel.Demo.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.top, 6)
            .onChange(of: model.demo) { _, value in
                if value == .wrong { withAnimation(.linear(duration: 0.4)) { model.wrongShakes += 1 } }
            }

            DemoPreview(demo: model.demo, shakes: model.wrongShakes)
                .frame(height: 150)

            Text(demoCaption)
                .font(Fonts.small)
                .foregroundStyle(.secondary)
                .animation(nil, value: model.demo)
        }
    }

    private var demoCaption: String {
        switch model.demo {
        case .real: return "Opens in its usual app with everything in it."
        case .decoy: return "Opens in the same app, same name in the title bar, nothing inside."
        case .wrong: return "Anything else gets a plain “Incorrect password”."
        }
    }

    private var pair: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.hadPair ? "Your pair is saved." : "Choose your pair.").font(Fonts.display(26))
            Text(model.hadPair
                 ? "You already set a real password and decoy word. Type a new pair to replace it, or keep the one you have."
                 : "Every file you lock uses these two. You can set a different pair for a single file when you lock it.")
                .font(Fonts.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PairFields(real: $model.real, confirm: $model.confirm, decoy: $model.decoy,
                       revealed: $model.revealed, focus: $focus)
                .padding(.top, 2)

            if let problem = model.pairProblem {
                Text(problem).font(Fonts.small).foregroundStyle(Palette.warning)
            } else if let note = PairRules.note(real: model.real, decoy: model.decoy) {
                Text(note).font(Fonts.small).foregroundStyle(.secondary)
            } else {
                Text("Forget it later? Settings can show your pair once you confirm it's you with Touch ID or your Mac password.")
                    .font(Fonts.small)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { if !model.hadPair { focus = .real } }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're set.").font(Fonts.display(26))
            Text("To lock a file, right-click it in Finder and choose Services, then Lock with Decoy Lock. Or drop it on the menu bar icon. Only the files you lock open through Decoy Lock; everything else opens as it always has.")
                .font(Fonts.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Open Decoy Lock when I log in", isOn: $openAtLogin)
                Toggle("Show the menu bar icon", isOn: $showMenuBarIcon)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.top, 6)

            Text("Keeping it open at login means locked files open without a pause, and spare copies get cleaned up after a restart.")
                .font(Fonts.small)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if model.step != .meet {
                Button("Back") { go(-1) }
                    .controlSize(.large)
            }
            Spacer()
            switch model.step {
            case .meet:
                Button("Set Up") { go(1) }.actionButton()
            case .pair:
                if model.hadPair && model.real.isEmpty && model.decoy.isEmpty {
                    Button("Keep My Pair") { go(1) }.actionButton()
                } else {
                    Button("Save Pair") { savePair() }.actionButton()
                }
            case .done:
                Button("Done") { finish() }.actionButton()
            }
        }
    }

    private func go(_ delta: Int) {
        guard let next = OnboardingModel.Step(rawValue: model.step.rawValue + delta) else { return }
        focus = nil
        model.pairProblem = nil
        withAnimation(.easeInOut(duration: 0.2)) { model.step = next }
    }

    private func savePair() {
        if let problem = PairRules.problem(real: model.real, confirm: model.confirm, decoy: model.decoy) {
            model.pairProblem = problem
            return
        }
        do {
            try PairStore.save(Pair(real: model.real, decoy: model.decoy))
            model.real = ""; model.confirm = ""; model.decoy = ""
            go(1)
        } catch {
            model.pairProblem = error.localizedDescription
        }
    }

    private func finish() {
        LoginItem.set(openAtLogin)
        Prefs.onboardingDone = true
        close()
    }
}

/// A file type and the app its unlocked copies open in.
struct TypeRow: View {
    let type: SupportedType

    var body: some View {
        let app = DefaultApps.shared.handOffApp(for: type)
        HStack(spacing: 12) {
            Image(nsImage: app.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: type.utType))
                .resizable()
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(type.label) (.\(type.ext))").font(.system(size: 12.5, weight: .medium))
                Text("Unlocked copies open in \(DefaultApps.shared.appName(app))")
                    .font(Fonts.small)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

struct StepDots: View {
    let current: Int
    let count: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Palette.ink : Palette.dusk.opacity(0.35))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

/// A tiny window showing what each kind of password gets you.
struct DemoPreview: View {
    let demo: OnboardingModel.Demo
    let shakes: CGFloat

    private let rows: [(String, [String])] = [
        ("Rent", ["1,450", "1,450", "1,450"]),
        ("Food", ["320", "295", "340"]),
        ("Savings", ["600", "650", "700"]),
        ("Total", ["2,370", "2,395", "2,490"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color(nsColor: .tertiaryLabelColor)).frame(width: 7, height: 7) }
                Spacer()
                Text("Budget.xlsx").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 31, height: 1)
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            ZStack {
                if demo == .wrong {
                    wrongBox.transition(.opacity)
                } else {
                    sheet.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor)))
        .animation(.easeInOut(duration: 0.22), value: demo)
        .accessibilityElement()
        .accessibilityLabel(demo == .real ? "A spreadsheet full of numbers" : demo == .decoy ? "The same spreadsheet, empty" : "An incorrect password message")
    }

    private var sheet: some View {
        let filled = demo == .real
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                headerCell("")
                ForEach(["A", "B", "C", "D"], id: \.self) { headerCell($0) }
            }
            GridRow {
                headerCell("1")
                cell("", bold: true)
                ForEach(["Jan", "Feb", "Mar"], id: \.self) { cell(filled ? $0 : "", bold: true) }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    headerCell("\(index + 2)")
                    cell(filled ? row.0 : "", bold: row.0 == "Total")
                    ForEach(Array(row.1.enumerated()), id: \.offset) { _, value in
                        cell(filled ? value : "", bold: row.0 == "Total", numeric: true)
                    }
                }
            }
        }
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: text.count <= 1 && Int(text) != nil || text.isEmpty ? 22 : .infinity, maxHeight: .infinity)
            .frame(height: 17)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            .border(Color(nsColor: .separatorColor).opacity(0.5), width: 0.5)
    }

    private func cell(_ text: String, bold: Bool = false, numeric: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: bold ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: numeric ? .trailing : .leading)
            .padding(.horizontal, 5)
            .frame(height: 19)
            .border(Color(nsColor: .separatorColor).opacity(0.5), width: 0.5)
    }

    private var wrongBox: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor))
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(alignment: .leading) {
                    Text("••••••••").font(.system(size: 11)).padding(.leading, 8).foregroundStyle(.secondary)
                }
                .frame(width: 170, height: 22)
                .modifier(Shake(animatableData: shakes))
            Text("Incorrect password").font(.system(size: 10.5)).foregroundStyle(Color(nsColor: .systemRed))
        }
    }
}
