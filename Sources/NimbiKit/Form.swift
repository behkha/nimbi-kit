import SwiftUI

/// The shape the cloud takes (DESIGN.md 3.5). Every app's cloud is `.cloud`; Tempo lets it become
/// the tool for the moment: an hourglass while you focus, a bell when time is up, a mug on a
/// break, a crescent moon on a long one. Skin, face, eyes, gaze and moods stay the same, and the
/// outline springs from one shape to the next.
public enum CloudForm: String, CaseIterable, Hashable, Sendable {
    case cloud, hourglass, bell, mug, moon

    /// Where the face sits, as a fraction of the size from the middle (the cloud looks a little
    /// to the right, like the icon).
    var face: CGPoint {
        switch self {
        case .cloud: return CGPoint(x: 0.08, y: 0)
        case .hourglass: return CGPoint(x: 0, y: 0.27)
        case .bell: return CGPoint(x: 0, y: 0.04)
        case .mug: return CGPoint(x: -0.06, y: 0.07)
        case .moon: return CGPoint(x: -0.22, y: 0.07)
        }
    }

    /// Eye size against the cloud's: smaller where the shape is narrow.
    var eyes: CGFloat {
        switch self {
        case .cloud: return 1
        case .hourglass: return 0.7
        case .bell, .mug: return 0.9
        case .moon: return 0.78
        }
    }

    /// How much of the liquid ring's core shows behind it: none past thin shapes, or it would
    /// glow through the hourglass's waist as a ball.
    var core: CGFloat {
        switch self {
        case .cloud: return 1
        case .bell, .mug: return 0.55
        case .hourglass, .moon: return 0.3
        }
    }

    /// The outline around the origin with radius 1, y down: `Outline.count` points, clockwise
    /// from the top, so any two forms morph point by point.
    var outline: Outline { Outline.cache[self] ?? .zero }

    fileprivate var points: [CGPoint] {
        switch self {
        case .cloud:
            // DESIGN.md 3.1, the same formula as CloudShape, starting at the top.
            return (0..<Outline.count).map { i in
                let t = -Double.pi / 2 + Double(i) / Double(Outline.count) * 2 * .pi
                let lobe = pow(abs(cos(4 * t + 0.2)), 0.7)
                let k = 0.93 + 0.043 * (2 * lobe - 1) + 0.012 * sin(2 * t + 1)
                return CGPoint(x: k * cos(t), y: k * sin(t))
            }
        case .hourglass:
            return Self.resample(Self.smooth(Self.polygon([
                (-0.62, -0.92), (0.62, -0.92), (0.62, -0.74), (0.13, -0.1), (0.13, 0.1), (0.66, 0.74),
                (0.66, 0.92), (-0.66, 0.92), (-0.66, 0.74), (-0.13, 0.1), (-0.13, -0.1), (-0.62, -0.74),
            ]), passes: 4))
        case .bell:
            return Self.resample(Self.smooth(Self.polygon([
                (-0.1, -0.94), (0.1, -0.94), (0.13, -0.8), (0.44, -0.64), (0.6, -0.2), (0.64, 0.36), (0.9, 0.66),
                (0.9, 0.8), (-0.9, 0.8), (-0.9, 0.66), (-0.64, 0.36), (-0.6, -0.2), (-0.44, -0.64), (-0.13, -0.8),
            ]), passes: 4))
        case .mug:
            return Self.resample(Self.smooth(Self.polygon([
                (-0.66, -0.5), (0.44, -0.5), (0.44, -0.34), (0.82, -0.3), (0.92, 0.04), (0.8, 0.38), (0.44, 0.42),
                (0.44, 0.6), (0.26, 0.82), (-0.48, 0.82), (-0.66, 0.6),
            ]), passes: 4))
        case .moon:
            return Self.resample(Self.smooth(Self.crescent(), passes: 3))
        }
    }

    // MARK: Building outlines

    private static func polygon(_ corners: [(CGFloat, CGFloat)], steps: Int = 40) -> [CGPoint] {
        var out: [CGPoint] = []
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            for k in 0..<steps {
                let f = CGFloat(k) / CGFloat(steps)
                out.append(CGPoint(x: a.0 + (b.0 - a.0) * f, y: a.1 + (b.1 - a.1) * f))
            }
        }
        return out
    }

    /// Rounds the corners: each pass pulls every point toward its neighbours.
    private static func smooth(_ points: [CGPoint], passes: Int) -> [CGPoint] {
        var p = points
        let n = p.count
        for _ in 0..<passes {
            p = (0..<n).map { i in
                let a = p[(i - 1 + n) % n], b = p[(i + 1) % n], c = p[i]
                return CGPoint(x: (a.x + 2 * c.x + b.x) / 4, y: (a.y + 2 * c.y + b.y) / 4)
            }
        }
        return p
    }

    /// A lit crescent: a disc with a second disc taken out of its upper right.
    private static func crescent() -> [CGPoint] {
        let outer: CGFloat = 0.84, inner: CGFloat = 0.72, cut = CGPoint(x: 0.36, y: -0.26)
        var lit: [(CGPoint, Double)] = []
        for i in 0..<720 {
            let t = Double(i) / 720 * 2 * .pi
            let p = CGPoint(x: outer * cos(t), y: outer * sin(t))
            if hypot(p.x - cut.x, p.y - cut.y) >= inner { lit.append((p, t)) }
        }
        // Start the lit arc after the gap, so it runs in one piece.
        var gap = 0
        for i in 1..<lit.count where lit[i].1 - lit[i - 1].1 > 0.05 { gap = i }
        let arc = (lit[gap...] + lit[..<gap]).map(\.0)
        guard let first = arc.first, let last = arc.last else { return arc }
        // Then back along the cut, from the arc's end to its start.
        let t0 = atan2(last.y - cut.y, last.x - cut.x)
        var t1 = atan2(first.y - cut.y, first.x - cut.x)
        while t1 > t0 { t1 -= 2 * .pi }
        let back = (0...160).map { i -> CGPoint in
            let t = t0 + (t1 - t0) * CGFloat(i) / 160
            return CGPoint(x: cut.x + inner * cos(t), y: cut.y + inner * sin(t))
        }
        return arc + back
    }

    /// `Outline.count` points evenly spaced along the path, clockwise on screen, from the top.
    private static func resample(_ input: [CGPoint]) -> [CGPoint] {
        var pts = input
        var area: CGFloat = 0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            area += a.x * b.y - b.x * a.y
        }
        if area < 0 { pts.reverse() }
        var top = 0
        for (i, p) in pts.enumerated() {
            let t = pts[top]
            if p.y < t.y - 1e-6 || (abs(p.y - t.y) < 1e-6 && abs(p.x) < abs(t.x)) { top = i }
        }
        pts = Array(pts[top...] + pts[..<top])
        var lengths: [CGFloat] = [0]
        for i in 1...pts.count {
            let p = pts[i - 1], q = pts[i % pts.count]
            lengths.append(lengths[i - 1] + hypot(q.x - p.x, q.y - p.y))
        }
        let total = lengths[lengths.count - 1]
        var out: [CGPoint] = []
        var j = 0
        for k in 0..<Outline.count {
            let d = CGFloat(k) / CGFloat(Outline.count) * total
            while lengths[j + 1] < d { j += 1 }
            let p = pts[j], q = pts[(j + 1) % pts.count]
            let f = (d - lengths[j]) / max(lengths[j + 1] - lengths[j], 1e-9)
            out.append(CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f))
        }
        return out
    }
}

/// An outline as one long list of numbers, so SwiftUI can spring it from one form to another,
/// point by point (overshoot included: that's the squash and stretch).
public struct Outline: VectorArithmetic, Sendable {
    static let count = 240
    fileprivate static let cache: [CloudForm: Outline] = Dictionary(uniqueKeysWithValues: CloudForm.allCases.map { form in
        (form, Outline(values: form.points.flatMap { [Double($0.x), Double($0.y)] }))
    })

    var values: [Double]

    public static var zero: Outline { Outline(values: []) }

    public static func + (a: Outline, b: Outline) -> Outline { combine(a, b, +) }
    public static func - (a: Outline, b: Outline) -> Outline { combine(a, b, -) }

    /// `zero` has no points: it stands for all zeros at whatever length the other side has.
    private static func combine(_ a: Outline, _ b: Outline, _ op: (Double, Double) -> Double) -> Outline {
        if a.values.isEmpty { return Outline(values: b.values.map { op(0, $0) }) }
        if b.values.isEmpty { return a }
        return Outline(values: zip(a.values, b.values).map(op))
    }

    public mutating func scale(by rhs: Double) {
        for i in values.indices { values[i] *= rhs }
    }

    public var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }

    public static func == (a: Outline, b: Outline) -> Bool { a.values == b.values }
}

/// The cloud's outline in any form, morphing when the form changes. `.cloud` is `CloudShape`.
public struct FormShape: Shape {
    public var outline: Outline

    public init(_ form: CloudForm) { outline = form.outline }

    public var animatableData: Outline {
        get { outline }
        set { outline = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let v = outline.values
        var path = Path()
        guard v.count >= 4 else { return path }
        for i in stride(from: 0, to: v.count - 1, by: 2) {
            let p = CGPoint(x: rect.midX + CGFloat(v[i]) * r, y: rect.midY + CGFloat(v[i + 1]) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - What each form carries

/// The extras a form brings along, drawn with it: sand running through the hourglass (as
/// `progress` goes from 0 to 1) and steam off the mug.
struct FormExtras: View {
    var form: CloudForm
    var size: CGFloat
    var progress: Double
    var paused: Bool

    var body: some View {
        switch form {
        case .hourglass:
            Sand(size: size, progress: progress, paused: paused)
                .transition(.opacity)
        case .mug:
            Steam(size: size, paused: paused)
                .transition(.opacity)
        default:
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

/// Sand: a heap in the top bulb that sinks as time goes, a pile in the bottom one that grows,
/// and a thin stream between them while there's still sand on top.
private struct Sand: View {
    var size: CGFloat
    var progress: Double
    var paused: Bool

    var body: some View {
        let p = CGFloat(min(1, max(0, progress)))
        let r = size / 2
        let ink = Color(hex: "#24163A")
        ZStack {
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                // Top bulb: sand from the waist up to a level that drops as time passes.
                let topLevel = -0.1 - 0.72 * (1 - p)   // y of the sand's surface, in radius units
                var top = Path()
                top.move(to: CGPoint(x: c.x - halfWidth(topLevel) * r, y: c.y + topLevel * r))
                top.addLine(to: CGPoint(x: c.x + halfWidth(topLevel) * r, y: c.y + topLevel * r))
                top.addLine(to: CGPoint(x: c.x + 0.1 * r, y: c.y - 0.1 * r))
                top.addLine(to: CGPoint(x: c.x - 0.1 * r, y: c.y - 0.1 * r))
                top.closeSubpath()
                if p < 0.995 { ctx.fill(top, with: .color(ink.opacity(0.2))) }
                // Bottom bulb: a soft mound that rises with time.
                let height = 0.72 * p
                if height > 0.01 {
                    var pile = Path()
                    let floor = 0.86 as CGFloat
                    pile.move(to: CGPoint(x: c.x - 0.6 * r, y: c.y + floor * r))
                    pile.addQuadCurve(to: CGPoint(x: c.x + 0.6 * r, y: c.y + floor * r),
                                      control: CGPoint(x: c.x, y: c.y + (floor - 2 * height) * r))
                    pile.closeSubpath()
                    ctx.fill(pile, with: .color(ink.opacity(0.2)))
                }
            }
            if p > 0.001 && p < 0.995 {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, sz in
                        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                        // A falling stream of grains through the waist.
                        for i in 0..<6 {
                            let f = CGFloat((t * 1.6 + Double(i) / 6).truncatingRemainder(dividingBy: 1))
                            let y = c.y + (-0.08 + f * 0.8) * r
                            let d = max(1, size * 0.018)
                            ctx.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: y, width: d, height: d)),
                                     with: .color(ink.opacity(0.3)))
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    /// Half the hourglass's inner width at a height in the top bulb (radius units).
    private func halfWidth(_ y: CGFloat) -> CGFloat {
        let f = min(1, max(0, (-0.1 - y) / 0.64))
        return 0.1 + (0.56 - 0.1) * f
    }
}

/// Three wisps rising off the mug.
private struct Steam: View {
    var size: CGFloat
    var paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                // The canvas reaches above the mug, where the steam goes.
                let c = CGPoint(x: sz.width / 2, y: sz.height - size / 2), r = size / 2
                for i in 0..<3 {
                    var wisp = Path()
                    for k in 0...20 {
                        let f = CGFloat(k) / 20
                        let x = c.x + (CGFloat(i) - 1.2) * 0.3 * r + CGFloat(sin(Double(f) * 9 - t * 3 + Double(i))) * 0.06 * r
                        let y = c.y - 0.62 * r - f * 0.5 * r
                        if k == 0 { wisp.move(to: CGPoint(x: x, y: y)) } else { wisp.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let fade = 0.25 + 0.15 * sin(t * 1.3 + Double(i))
                    ctx.stroke(wisp, with: .color(.white.opacity(fade)),
                               style: StrokeStyle(lineWidth: max(1, size * 0.024), lineCap: .round))
                }
            }
        }
        .frame(width: size, height: size * 1.6)
        .offset(y: -size * 0.3)
        .allowsHitTesting(false)
    }
}
