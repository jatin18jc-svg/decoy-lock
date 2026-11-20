import SwiftUI

enum PairField: Hashable {
    case current, real, confirm, decoy
}

/// How the mascot reacts to whichever pair field has focus.
func mood(for field: PairField?, revealed: Bool) -> Mood {
    switch field {
    case .real, .confirm, .current: return revealed ? .peeking : .covering
    case .decoy: return .possum
    case nil: return .idle
    }
}

struct SecretField: View {
    let title: String
    @Binding var text: String
    let revealed: Bool
    let field: PairField
    var focus: FocusState<PairField?>.Binding

    var body: some View {
        Group {
            if revealed {
                TextField(title, text: $text.ignoringRepeats)
            } else {
                SecureField(title, text: $text.ignoringRepeats)
            }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
        .focused(focus, equals: field)
    }
}

/// Real password, confirmation and decoy word, with one shared "show" toggle.
struct PairFields: View {
    @Binding var real: String
    @Binding var confirm: String
    @Binding var decoy: String
    @Binding var revealed: Bool
    var focus: FocusState<PairField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Real password").font(.system(size: 12, weight: .semibold))
                SecretField(title: "Opens the file", text: $real, revealed: revealed, field: .real, focus: focus)
                SecretField(title: "Type it again", text: $confirm, revealed: revealed, field: .confirm, focus: focus)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Decoy word").font(.system(size: 12, weight: .semibold))
                SecretField(title: "Opens a blank copy", text: $decoy, revealed: revealed, field: .decoy, focus: focus)
                Text("Pick something you'd be fine saying out loud if someone asks.")
                    .font(Fonts.small)
                    .foregroundStyle(.secondary)
            }
            Toggle("Show what I'm typing", isOn: $revealed.ignoringRepeats)
                .toggleStyle(.checkbox)
                .font(Fonts.small)
        }
    }
}

extension Binding where Value: Equatable {
    /// AppKit text fields write their current value back when the appearance changes.
    /// Passed straight to an ObservableObject, that same-value write announces a change
    /// in the middle of a SwiftUI update, which crashes. This drops writes that change nothing.
    var ignoringRepeats: Binding<Value> {
        Binding(get: { wrappedValue }, set: { newValue in
            if newValue != wrappedValue { wrappedValue = newValue }
        })
    }
}
