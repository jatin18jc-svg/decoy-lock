import SwiftUI

/// What the mascot is doing. It's a document with possum ears, and it reacts to the
/// fields you're typing in: it covers its eyes for the real password and plays dead
/// (on its side, X eyes, tongue out) for the decoy word.
enum Mood: Equatable {
    case idle
    case covering   // eyes covered: real password field, hidden
    case peeking    // one paw down: real password field, revealed
    case possum     // playing dead: decoy word
    case happy
    case alert      // something is being dragged over it
    case worried
}

struct DocShape: Shape {
    var fold: CGFloat = 17
    var radius: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = radius
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        p.closeSubpath()
        return p
    }
}

struct FoldShape: Shape {
    var fold: CGFloat = 17
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold - 4))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - fold + 4, y: rect.minY + fold), control: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        p.closeSubpath()
        return p
    }
}

private struct XEye: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

private struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return p
    }
}

private struct Smile: Shape {
    var depth: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.midY + depth))
        return p
    }
}

private struct Whiskers: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Left side
        p.move(to: CGPoint(x: 31, y: 75)); p.addLine(to: CGPoint(x: 15, y: 71))
        p.move(to: CGPoint(x: 31, y: 79)); p.addLine(to: CGPoint(x: 15, y: 81))
        // Right side
        p.move(to: CGPoint(x: 69, y: 75)); p.addLine(to: CGPoint(x: 85, y: 71))
        p.move(to: CGPoint(x: 69, y: 79)); p.addLine(to: CGPoint(x: 85, y: 81))
        return p
    }
}

struct Mascot: View {
    var mood: Mood
    var size: CGFloat = 120

    @ViewState private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ink = Palette.mascotInk
    private let canvas = CGSize(width: 100, height: 124)

    var body: some View {
        let scale = size / canvas.height
        figure
            .frame(width: canvas.width, height: canvas.height)
            .rotationEffect(.degrees(mood == .possum ? -82 : 0))
            .offset(y: mood == .possum ? 10 : 0)
            .scaleEffect(mood == .possum ? 0.86 : (mood == .alert ? 1.06 : 1))
            .scaleEffect(scale)
            .frame(width: canvas.width * scale, height: canvas.height * scale)
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.62), value: mood)
            .task(id: mood) { await blinkLoop() }
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private var figure: some View {
        ZStack(alignment: .topLeading) {
            ear(at: CGPoint(x: 27, y: 15))
            ear(at: CGPoint(x: 71, y: 15))

            DocShape()
                .fill(Palette.mascotFur)
                .overlay(DocShape().stroke(ink, style: StrokeStyle(lineWidth: 3, lineJoin: .round)))
                .frame(width: 100, height: 106)
                .offset(y: 18)
            FoldShape()
                .fill(Palette.mascotShade)
                .overlay(FoldShape().stroke(ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round)))
                .frame(width: 100, height: 106)
                .offset(y: 18)

            Whiskers()
                .stroke(ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 100, height: 124)

            eyes

            Ellipse()
                .fill(Palette.mascotNose)
                .overlay(Ellipse().stroke(ink, lineWidth: 2))
                .frame(width: 14, height: 10)
                .position(x: 50, y: 74)

            mouth

            paws
        }
        .frame(width: 100, height: 124, alignment: .topLeading)
    }

    private func ear(at point: CGPoint) -> some View {
        ZStack {
            Circle().fill(Palette.mascotShade)
            Circle().stroke(ink, lineWidth: 3)
            Circle().fill(Palette.mascotNose.opacity(0.75)).padding(6)
        }
        .frame(width: 24, height: 24)
        .position(point)
    }

    @ViewBuilder private var eyes: some View {
        switch mood {
        case .possum:
            ForEach([36.0, 64.0], id: \.self) { x in
                XEye().stroke(ink, style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                    .frame(width: 9, height: 9)
                    .position(x: x, y: 58)
            }
        case .happy:
            ForEach([36.0, 64.0], id: \.self) { x in
                HappyEye().stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 11, height: 5)
                    .position(x: x, y: 59)
            }
        default:
            let big = mood == .alert
            ForEach([36.0, 64.0], id: \.self) { x in
                ZStack {
                    Ellipse().fill(ink)
                    Circle().fill(.white).frame(width: big ? 4 : 3).offset(x: 1.5, y: -2.5)
                }
                .frame(width: big ? 12 : 9, height: big ? 15 : 12)
                .scaleEffect(x: 1, y: blink ? 0.12 : 1)
                .position(x: x, y: 58)
            }
            if mood == .worried {
                brow(x: 36, angle: -14)
                brow(x: 64, angle: 14)
            }
        }
    }

    private func brow(x: CGFloat, angle: Double) -> some View {
        Capsule().fill(ink)
            .frame(width: 11, height: 2.6)
            .rotationEffect(.degrees(angle))
            .position(x: x, y: 47)
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .possum:
            // Tongue lolling out of a flat mouth.
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                .fill(Palette.mascotNose)
                .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4).stroke(ink, lineWidth: 1.8))
                .frame(width: 9, height: 12)
                .position(x: 52, y: 91)
        case .worried, .alert:
            Ellipse().stroke(ink, lineWidth: 2.2)
                .frame(width: 7, height: 6)
                .position(x: 50, y: 85)
        default:
            Smile(depth: mood == .happy ? 9 : 5)
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: mood == .happy ? 16 : 12, height: 8)
                .position(x: 50, y: 82)
        }
    }

    private var paws: some View {
        let left: CGFloat = mood == .covering || mood == .peeking ? 58 : 140
        let right: CGFloat = mood == .covering ? 58 : (mood == .peeking ? 100 : 140)
        return ZStack {
            paw.position(x: 35, y: left)
            paw.position(x: 65, y: right)
        }
        .opacity(mood == .covering || mood == .peeking ? 1 : 0)
    }

    private var paw: some View {
        ZStack {
            Ellipse().fill(Palette.mascotShade)
            Ellipse().stroke(ink, lineWidth: 2.5)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(ink.opacity(0.55)).frame(width: 1.6, height: 5) }
            }
            .offset(y: -3)
        }
        .frame(width: 25, height: 18)
    }

    private func blinkLoop() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 3.2...6.5) * 1_000_000_000))
            guard !Task.isCancelled, mood == .idle || mood == .worried || mood == .alert else { continue }
            withAnimation(.easeIn(duration: 0.07)) { blink = true }
            try? await Task.sleep(nanoseconds: 110_000_000)
            withAnimation(.easeOut(duration: 0.09)) { blink = false }
        }
    }

    private var accessibilityText: String {
        switch mood {
        case .idle: return "Decoy Lock mascot"
        case .covering: return "Mascot covering its eyes"
        case .peeking: return "Mascot peeking"
        case .possum: return "Mascot playing dead"
        case .happy: return "Mascot smiling"
        case .alert: return "Mascot watching"
        case .worried: return "Mascot looking worried"
        }
    }
}
