import SwiftUI

/// Weather around the cloud (DESIGN.md 3.5: the cloud stays the cloud; props sit next to it).
/// A sun or moon behind it, rain, snow or a bolt below it, fog or wind across it. The cloud's
/// mood, face and skin don't change.
public enum CloudWeather: Hashable, Sendable {
    case none
    case clear
    case partlyCloudy
    /// A clear (or fair) night: a crescent moon and stars.
    case clearNight
    /// 0…1, from drizzle to a downpour.
    case rain(Double)
    case thunder
    case snow
    case sleet
    case fog
    case wind
    /// 30° and more by day: an orange sun and shimmering air.
    case hot
}

/// The weather layer with its own pause: still under Reduce Motion, stopped while hidden.
struct WeatherAround: View {
    var weather: CloudWeather
    var size: CGFloat
    var behind: Bool
    @ViewState private var hidden = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WeatherLayer(weather: weather, size: size, behind: behind, paused: hidden || reduceMotion)
            .background(VisibilityProbe(hidden: $hidden))
            .transition(.opacity)
            .id(weather)
    }
}

/// Draws a `CloudWeather` around a cloud of `size`, in a frame twice its size centred on it.
/// `behind` draws what sits behind the cloud (sun, moon, stars, rain, snow, the bolt, far fog),
/// otherwise what's in front (near fog, wind, heat shimmer). Rain and snow fall all around the
/// cloud rather than only below it, so they still show when the cloud is cropped at a corner.
struct WeatherLayer: View {
    var weather: CloudWeather
    var size: CGFloat
    var behind: Bool
    /// Hidden window or Reduce Motion: one still frame.
    var paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
            Canvas { ctx, canvas in
                let t = paused ? 2.0 : context.date.timeIntervalSinceReferenceDate
                draw(&ctx, center: CGPoint(x: canvas.width / 2, y: canvas.height / 2), t: t)
            }
        }
        .frame(width: size * 2, height: size * 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: inout GraphicsContext, center c: CGPoint, t: Double) {
        let s = size
        switch (weather, behind) {
        case (.clear, true): sun(&ctx, at: CGPoint(x: c.x - s * 0.34, y: c.y - s * 0.36), radius: s * 0.24, color: Nimbi.Heat.yellow, t: t)
        case (.partlyCloudy, true): sun(&ctx, at: CGPoint(x: c.x - s * 0.3, y: c.y - s * 0.3), radius: s * 0.19, color: Nimbi.Heat.yellow, t: t)
        case (.hot, true): sun(&ctx, at: CGPoint(x: c.x - s * 0.34, y: c.y - s * 0.36), radius: s * 0.25, color: Nimbi.Heat.orange, t: t * 1.6)
        case (.hot, false): shimmer(&ctx, c: c, s: s, t: t)
        case (.clearNight, true):
            stars(&ctx, c: c, s: s, t: t)
            moon(&ctx, at: CGPoint(x: c.x + s * 0.4, y: c.y - s * 0.4), radius: s * 0.16)
        case (.rain(let intensity), true): rain(&ctx, c: c, s: s, t: t, intensity: intensity)
        case (.thunder, true):
            rain(&ctx, c: c, s: s, t: t, intensity: 0.7)
            bolt(&ctx, c: c, s: s, t: t)
        case (.snow, true): snow(&ctx, c: c, s: s, t: t, count: 16)
        case (.sleet, true):
            rain(&ctx, c: c, s: s, t: t, intensity: 0.35)
            snow(&ctx, c: c, s: s, t: t, count: 8)
        case (.fog, let back): fog(&ctx, c: c, s: s, t: t, behind: back)
        case (.wind, false): wind(&ctx, c: c, s: s, t: t)
        default: break
        }
    }

    // MARK: Behind

    private func sun(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat, color: Color, t: Double) {
        var glow = ctx
        glow.addFilter(.blur(radius: r * 0.6))
        glow.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.3, y: p.y - r * 1.3, width: r * 2.6, height: r * 2.6)), with: .color(color.opacity(0.35)))
        let turn = t * 0.12
        var rays = Path()
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi + turn
            rays.move(to: CGPoint(x: p.x + cos(a) * r * 1.3, y: p.y + sin(a) * r * 1.3))
            rays.addLine(to: CGPoint(x: p.x + cos(a) * r * 1.65, y: p.y + sin(a) * r * 1.65))
        }
        ctx.stroke(rays, with: .color(color), style: StrokeStyle(lineWidth: r * 0.22, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    private func moon(_ ctx: inout GraphicsContext, at p: CGPoint, radius r: CGFloat) {
        let disc = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        let bite = Path(ellipseIn: CGRect(x: p.x - r * 0.45, y: p.y - r * 1.35, width: r * 1.9, height: r * 1.9))
        var moon = ctx
        moon.clip(to: bite, options: .inverse)
        var glow = moon
        glow.addFilter(.blur(radius: r * 0.5))
        glow.fill(disc, with: .color(Color(hex: "#F6F0C8").opacity(0.5)))
        moon.fill(disc, with: .color(Color(hex: "#F6F0C8")))
    }

    private func stars(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, t: Double) {
        let spots: [(CGFloat, CGFloat, Double)] = [(-0.62, -0.5, 0), (-0.3, -0.75, 1.7), (0.1, -0.82, 3.1), (0.72, -0.1, 4.4),
                                                    (-0.78, -0.12, 2.3), (0.6, -0.75, 5.2)]
        for (x, y, phase) in spots {
            let a = 0.35 + 0.65 * abs(sin(t * 1.2 + phase))
            let r = s * 0.022
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + x * s - r, y: c.y + y * s - r, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(a)))
        }
    }

    // MARK: In front

    /// Drops falling past the cloud, more, faster and thicker with heavier rain.
    private func rain(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, t: Double, intensity: Double) {
        let count = 9 + Int(intensity * 14)
        let speed = 0.55 + intensity * 0.7
        for i in 0..<count {
            let seed = Double(i) * 0.618_034
            let phase = (t * speed + seed).truncatingRemainder(dividingBy: 1)
            let x = c.x + s * CGFloat(-0.92 + (seed * 7).truncatingRemainder(dividingBy: 1) * 1.84)
            let y = c.y + s * CGFloat(-0.95 + phase * 1.9)
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - s * 0.025, y: y + s * (0.07 + 0.04 * intensity)))
            ctx.stroke(drop, with: .color(Nimbi.State.rain.opacity(0.85 * sin(phase * .pi))),
                       style: StrokeStyle(lineWidth: s * (0.022 + 0.01 * intensity), lineCap: .round))
        }
    }

    private func snow(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, t: Double, count: Int) {
        for i in 0..<count {
            let seed = Double(i) * 0.618_034
            let phase = (t * 0.16 + seed).truncatingRemainder(dividingBy: 1)
            let x = c.x + s * CGFloat(-0.9 + (seed * 5).truncatingRemainder(dividingBy: 1) * 1.8 + 0.05 * sin(t * 1.4 + seed * 9))
            let y = c.y + s * CGFloat(-0.95 + phase * 1.9)
            let r = s * CGFloat(0.022 + 0.012 * (seed * 3).truncatingRemainder(dividingBy: 1))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(hex: "#EEF6FF").opacity(0.9 * sin(phase * .pi))))
        }
    }

    /// A bolt striking beside the cloud, flickering now and then.
    private func bolt(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 3.2)
        let on = cycle < 0.09 || (cycle > 0.16 && cycle < 0.24) || cycle > 0.6
        guard on else { return }
        let x = c.x - s * 0.62, y = c.y - s * 0.2, k = s * 0.42
        var p = Path()
        p.move(to: CGPoint(x: x + k * 0.1, y: y))
        p.addLine(to: CGPoint(x: x - k * 0.32, y: y + k * 0.55))
        p.addLine(to: CGPoint(x: x - k * 0.04, y: y + k * 0.55))
        p.addLine(to: CGPoint(x: x - k * 0.2, y: y + k))
        p.addLine(to: CGPoint(x: x + k * 0.34, y: y + k * 0.38))
        p.addLine(to: CGPoint(x: x + k * 0.06, y: y + k * 0.38))
        p.addLine(to: CGPoint(x: x + k * 0.26, y: y))
        p.closeSubpath()
        if cycle < 0.24 {
            var flash = ctx
            flash.addFilter(.blur(radius: s * 0.25))
            flash.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.95, y: c.y - s * 0.7, width: s * 1.7, height: s * 1.4)),
                       with: .color(Color(hex: "#FFF6D6").opacity(0.35)))
        }
        ctx.fill(p, with: .color(Nimbi.Heat.yellow))
    }

    private func fog(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, t: Double, behind: Bool) {
        let rows: [CGFloat] = behind ? [-0.22, 0.12] : [0.3, 0.52]
        for (i, row) in rows.enumerated() {
            let drift = CGFloat(sin(t * 0.25 + Double(i) * 2.1)) * s * 0.25
            let rect = CGRect(x: c.x - s * 0.85 + drift, y: c.y + row * s, width: s * 1.7, height: s * 0.11)
            let band = Path(roundedRect: rect, cornerRadius: s * 0.055)
            ctx.fill(band, with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(behind ? 0.12 : 0.22), .white.opacity(0)]),
                                                 startPoint: CGPoint(x: rect.minX, y: rect.midY),
                                                 endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
        }
    }

    private func wind(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, t: Double) {
        for i in 0..<4 {
            let seed = Double(i) * 0.37
            let phase = (t * 0.55 + seed).truncatingRemainder(dividingBy: 1)
            let x = c.x + s * CGFloat(0.95 - phase * 1.9)
            let y = c.y + s * CGFloat(-0.35 + Double(i) * 0.24)
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addQuadCurve(to: CGPoint(x: x + s * 0.32, y: y), control: CGPoint(x: x + s * 0.16, y: y - s * 0.06))
            let fade = sin(phase * .pi)
            ctx.stroke(streak, with: .color(.white.opacity(0.4 * fade)), style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
        }
    }

    private func shimmer(_ ctx: inout GraphicsContext, c: CGPoint, s: CGFloat, t: Double) {
        for i in 0..<3 {
            var line = Path()
            let y0 = c.y + s * CGFloat(0.42 + Double(i) * 0.1)
            for step in 0...24 {
                let x = c.x + s * CGFloat(-0.45 + Double(step) / 24 * 0.9)
                let y = y0 + s * 0.02 * CGFloat(sin(Double(step) * 0.8 + t * 3 + Double(i)))
                step == 0 ? line.move(to: CGPoint(x: x, y: y)) : line.addLine(to: CGPoint(x: x, y: y))
            }
            ctx.stroke(line, with: .color(Nimbi.Heat.orange.opacity(0.45)), style: StrokeStyle(lineWidth: s * 0.014, lineCap: .round))
        }
    }
}
