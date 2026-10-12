import SwiftUI
import AppKit

// MARK: - Panels

/// The panel behind cards, lists and menus: solid near-black with a faint rim. "Black" goes all
/// the way to black. Panels are solid, not glass: glass behind dense text hurts readability.
public struct PanelBackground: View {
    public var cornerRadius: CGFloat
    @ObservedObject private var look = NimbiAppearance.shared
    @Environment(\.hangsFromPill) private var hangsFromPill

    public init(cornerRadius: CGFloat = 18) { self.cornerRadius = cornerRadius }

    public var body: some View {
        if look.dock == .notch && hangsFromPill {
            // Hanging from the notch island: pure black with a flat top, so the two read as one piece.
            IslandBody(radius: cornerRadius + 4).fill(Color.black)
        } else {
            rounded
        }
    }

    private var rounded: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(look.theme == .black ? Nimbi.Surface.panelBlack : Nimbi.Surface.panel)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Nimbi.Line.rim, lineWidth: 0.75)
            )
    }
}

/// A panel hanging from the notch island: square on top (where it meets the island), rounded below.
public struct IslandBody: Shape {
    public var radius: CGFloat

    public init(radius: CGFloat) { self.radius = radius }

    public func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        p.closeSubpath()
        return p
    }
}

private struct HangsFromPillKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The panel opens out of the pill (a card, a list, the settings menu). At the notch those
    /// hang from the island and drop their top corners.
    public var hangsFromPill: Bool {
        get { self[HangsFromPillKey.self] }
        set { self[HangsFromPillKey.self] = newValue }
    }
}

extension View {
    /// The soft shadow under every floating panel, with room around it so the window never clips it.
    public func floatingPanelShadow() -> some View {
        shadow(color: .black.opacity(0.32), radius: 14, y: 7)
            .padding(16)
            .padding(.bottom, 8)
    }
}

/// Hosting view that tells its owner when the SwiftUI content wants a different size, so a
/// borderless panel window can always match its content (and keep its top edge in place).
public final class SizeReportingHostingView<Content: View>: NSHostingView<Content> {
    public var onFittingSizeChange: (() -> Void)?
    private var lastSize: NSSize = .zero

    public required init(rootView: Content) { super.init(rootView: rootView) }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    override public func layout() {
        super.layout()
        report()
    }

    override public func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.report() }
    }

    private func report() {
        let size = fittingSize
        guard abs(size.width - lastSize.width) > 0.5 || abs(size.height - lastSize.height) > 0.5 else { return }
        lastSize = size
        DispatchQueue.main.async { [weak self] in self?.onFittingSizeChange?() }
    }
}

// MARK: - Keys and buttons

/// Small rounded key hint shown next to the control it triggers ("esc", "J", "E").
public struct KeyHint: View {
    public var key: String
    /// Drawn on a light button (dark text and chip).
    public var onLight: Bool
    @ObservedObject private var look = NimbiAppearance.shared

    public init(key: String, onLight: Bool = false) {
        self.key = key
        self.onLight = onLight
    }

    public var body: some View {
        Text(key)
            .font(look.font(9.5, .semibold))
            .foregroundStyle(onLight ? Color.black.opacity(0.5) : Color.white.opacity(0.6))
            .padding(.horizontal, key.count > 1 ? 5 : 0)
            .frame(minWidth: 17, minHeight: 17)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(onLight ? Color.black.opacity(0.09) : Color.white.opacity(0.11)))
    }
}

/// White capsule, black text: the one primary action.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.75 : 0.95)))
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .overlay(Capsule().stroke(Nimbi.Line.row, lineWidth: 1))
    }
}

/// The capsule buttons in panels: plain, prominent (blue), light (white) or destructive (red
/// text on a red wash). They grow with the text size.
public struct PillButtonStyle: ButtonStyle {
    public var prominent: Bool
    public var light: Bool
    public var destructive: Bool
    /// The label ends with a key hint, which sits closer to the edge.
    public var hint: Bool

    public init(prominent: Bool = false, light: Bool = false, destructive: Bool = false, hint: Bool = false) {
        self.prominent = prominent
        self.light = light
        self.destructive = destructive
        self.hint = hint
    }

    public func makeBody(configuration: Configuration) -> some View {
        let look = NimbiAppearance.shared
        return configuration.label
            .font(look.font(11.5, .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(light ? Color.black.opacity(0.88) : (destructive ? Nimbi.State.destructive : .white))
            .padding(.leading, 10).padding(.trailing, hint ? 4 : 10).padding(.vertical, 3)
            .frame(minHeight: 25)
            .background(
                Capsule().fill(light ? Color.white.opacity(configuration.isPressed ? 0.7 : 0.94)
                               : prominent ? Nimbi.State.working.opacity(configuration.isPressed ? 0.7 : 1)
                               : destructive ? Nimbi.State.destructive.opacity(configuration.isPressed ? 0.22 : 0.12)
                               : Color.white.opacity(configuration.isPressed ? 0.16 : 0.09))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

// MARK: - Status

/// Spinner arc or dot for something's status: a blue arc while it works, a dot in `color`
/// otherwise, a flickering ember while it runs hot. Pops when `value` changes to something that
/// isn't working.
public struct StatusGlyph<Value: Equatable>: View {
    public var value: Value
    public var working: Bool
    public var color: Color
    public var hot: Bool
    public var size: CGFloat
    /// How far it swells when it changes (0 turns the pop off).
    public var pop: CGFloat

    public init(_ value: Value, working: Bool, color: Color, hot: Bool = false, size: CGFloat = 9, pop: CGFloat = 1.6) {
        self.value = value
        self.working = working
        self.color = color
        self.hot = hot
        self.size = size
        self.pop = pop
    }

    public var body: some View {
        GlyphFace(working: working, color: color, hot: hot, size: size)
            .id("\(working)-\(hot)")   // fresh view (and animation) every time work starts again
            .popOnChange(of: Change(value: value, working: working), strength: pop) { !$0.working && pop > 0 }
    }

    /// The value with whether it means working, so the pop sees both as they are after the change.
    private struct Change: Equatable {
        var value: Value
        var working: Bool
    }
}

extension StatusGlyph where Value == Color {
    /// A glyph that pops when its color changes.
    public init(working: Bool, color: Color, hot: Bool = false, size: CGFloat = 9, pop: CGFloat = 1.6) {
        self.init(color, working: working, color: color, hot: hot, size: size, pop: pop)
    }
}

private struct GlyphFace: View {
    var working: Bool
    var color: Color
    var hot: Bool
    var size: CGFloat
    @ViewState private var spin = false

    var body: some View {
        Group {
            if hot {
                // A flickering ember: the job heating the Mac.
                TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let flicker = 0.85 + 0.15 * sin(t * 13) * sin(t * 7 + 1)
                    Circle()
                        .fill(RadialGradient(colors: [Nimbi.Heat.core, Nimbi.Heat.yellow, Nimbi.Heat.orange, Nimbi.Heat.red],
                                             center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: size * 0.6))
                        .scaleEffect(flicker)
                        .shadow(color: Nimbi.Heat.orange.opacity(0.9), radius: size * 0.5 * flicker)
                }
            } else if working {
                Circle()
                    .trim(from: 0, to: 0.66)
                    .stroke(Nimbi.State.working, style: StrokeStyle(lineWidth: max(1.6, size * 0.24), lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                    }
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Pops a status glyph when its status changes (a job finished, or started asking): it swells
/// for a moment and settles.
public struct StatusPop<V: Equatable>: ViewModifier {
    public var value: V
    public var strength: CGFloat
    /// Only pop for changes this returns true for.
    public var when: (V) -> Bool
    @ViewState private var scale: CGFloat = 1

    public init(value: V, strength: CGFloat = 1.5, when: @escaping (V) -> Bool = { _ in true }) {
        self.value = value
        self.strength = strength
        self.when = when
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: value) { v in
                guard when(v) else { return }
                scale = 0.35
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { scale = strength }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { scale = 1 }
                }
            }
    }
}

extension View {
    public func popOnChange<V: Equatable>(of value: V, strength: CGFloat = 1.5, when: @escaping (V) -> Bool = { _ in true }) -> some View {
        modifier(StatusPop(value: value, strength: strength, when: when))
    }
}

/// Red level bars that replace the mic while it listens.
public struct ListeningBars: View {
    public var color: Color
    public var height: CGFloat

    public init(color: Color = Nimbi.State.listening, height: CGFloat = 13) {
        self.color = color
        self.height = height
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: height * 0.16) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (5.5 + Double(i) * 1.3) + Double(i) * 1.7
                    let level = 0.35 + 0.65 * abs(sin(phase) * cos(phase * 0.37))
                    Capsule()
                        .fill(color)
                        .frame(width: height * 0.17, height: max(height * 0.22, height * level))
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - The pill

/// The collapsed pill: a tab rounded on its left that flares into the screen edge at both ends,
/// so it reads as part of the edge rather than a chip floating next to it.
public struct EdgeTab: Shape {
    public var radius: CGFloat
    public var flare: CGFloat
    /// On the left edge: rounded on its right, flaring into the left edge.
    public var mirrored: Bool

    public init(radius: CGFloat = 5, flare: CGFloat = 5, mirrored: Bool = false) {
        self.radius = radius
        self.flare = flare
        self.mirrored = mirrored
    }

    public func path(in rect: CGRect) -> Path {
        let p = rightEdge(in: rect)
        guard mirrored else { return p }
        return p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }

    private func rightEdge(in rect: CGRect) -> Path {
        let f = min(flare, rect.height / 4)
        let top = rect.minY + f, bottom = rect.maxY - f
        let r = min(radius, (bottom - top) / 2, rect.width - f)
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.minX, y: top), radius: f)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.minX, y: bottom), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.maxX, y: bottom), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: f)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The expanded pill's chrome. On macOS 26 and later it is Liquid Glass, smoked dark so the
/// white glyphs stay legible on any wallpaper; pieces that share a glass container blend and
/// morph into each other by `id`. Earlier systems get a flat dark fill under a thin rim.
public struct PillChrome<S: Shape>: ViewModifier {
    public var shape: S
    public var active: Bool
    public var id: String?
    public var namespace: Namespace.ID?
    /// Off while pieces overlap as one, so their smoke doesn't stack into darker bands.
    public var smoke: Bool

    public init(shape: S, active: Bool = false, id: String? = nil, namespace: Namespace.ID? = nil, smoke: Bool = true) {
        self.shape = shape
        self.active = active
        self.id = id
        self.namespace = namespace
        self.smoke = smoke
    }

    public func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            glass(content)
        } else {
            content
                .background(shape.fill(active ? Nimbi.Surface.pillActive : Nimbi.Surface.pill))
                .overlay(shape.stroke(active ? Nimbi.Line.pillActive : Nimbi.Line.pill, lineWidth: 1))
                .shadow(color: .black.opacity(0.32), radius: 5, y: 2)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder private func glass(_ content: Content) -> some View {
        // A black tint barely darkens glass; smoke laid under it does, and keeps the glass's edge light.
        let glassy = content
            .background(shape.fill(Color.black.opacity(smoke ? (active ? 0.22 : 0.48) : 0)))
            .glassEffect(.regular, in: shape)
        if let id, let namespace {
            glassy.glassEffectID(id, in: namespace)
        } else {
            glassy
        }
    }
}

extension View {
    public func pillChrome<S: Shape>(_ shape: S, active: Bool = false, id: String? = nil, in namespace: Namespace.ID? = nil,
                                     smoke: Bool = true) -> some View {
        modifier(PillChrome(shape: shape, active: active, id: id, namespace: namespace, smoke: smoke))
    }

    /// Lets the pill's glass pieces melt into each other as they move (macOS 26+).
    @ViewBuilder public func glassGroup(spacing: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }
}

// MARK: - Hover

/// Floating label shown beside a pill button while hovering it: toward the middle of the screen
/// (left of the button on the right edge, right of it on the left edge, below it at the notch).
public struct HoverTip: ViewModifier {
    public var text: String
    @ViewState private var hover = false
    @ObservedObject private var look = NimbiAppearance.shared

    public init(text: String) { self.text = text }

    private var alignment: Alignment {
        switch look.dock {
        case .right: return .trailing
        case .left: return .leading
        case .notch: return .bottom
        }
    }

    private var offset: CGSize {
        switch look.dock {
        case .right: return CGSize(width: -Self.gap * look.pillScale, height: 0)
        case .left: return CGSize(width: Self.gap * look.pillScale, height: 0)
        case .notch: return CGSize(width: 0, height: 28)
        }
    }

    /// From the button's outer edge to the label's near end, at pill size 1.
    public static let gap: CGFloat = 44
    /// The widest a label's text gets at text size 1 (it grows with the text size). The pill's
    /// window should be sized to fit it; a longer label is cut short with "…" rather than by the
    /// window's edge.
    public static let maxTextWidth: CGFloat = 176
    public static let padding: CGFloat = 8

    public static func font(textScale: Double) -> NSFont {
        .systemFont(ofSize: 11 * CGFloat(textScale), weight: .medium)
    }

    /// The width of a label's text: as measured (with a point to spare: SwiftUI rounds up), but
    /// no wider than there is room for.
    public static func textWidth(_ text: String, textScale: Double) -> CGFloat {
        let measured = (text as NSString).size(withAttributes: [.font: font(textScale: textScale)]).width
        return min(ceil(measured) + 2, maxTextWidth * CGFloat(textScale))
    }

    public func body(content: Content) -> some View {
        content
            .pointerHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
            .overlay(alignment: alignment) {
                if hover && look.showTooltips {
                    Text(text)
                        .font(look.font(11, .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: Self.textWidth(text, textScale: look.textScale))
                        .fixedSize()
                        .padding(.horizontal, Self.padding).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.85)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        .offset(offset)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .zIndex(hover ? 1 : 0)
    }
}

extension View {
    public func hoverTip(_ text: String) -> some View { modifier(HoverTip(text: text)) }

    /// A soft white halo around a pill button while the pointer is on it.
    public func hoverHalo<S: Shape>(_ shape: S) -> some View { modifier(HoverHalo(shape: shape)) }
}

/// The pill's hover state: a faint white wash over the button and a low glow around it.
public struct HoverHalo<S: Shape>: ViewModifier {
    public var shape: S
    @ViewState private var hover = false

    public init(shape: S) { self.shape = shape }

    public func body(content: Content) -> some View {
        content
            .background(
                shape.fill(Color.white.opacity(hover ? 0.2 : 0))
                    .blur(radius: 7)
                    .scaleEffect(hover ? 1.18 : 0.9)
                    .allowsHitTesting(false)
            )
            .overlay(
                shape.fill(Color.white.opacity(hover ? 0.11 : 0))
                    .overlay(shape.stroke(Color.white.opacity(hover ? 0.18 : 0), lineWidth: 0.75))
                    .allowsHitTesting(false)
            )
            .pointerHover { h in withAnimation(.easeOut(duration: 0.16)) { hover = h } }
    }
}

// MARK: - Undo bar

/// DESIGN.md 8: "✓ Session reset · esc to undo", with a 2.5 pt blue line draining over the undo
/// window (`Nimbi.Motion.undoWindow`, or `undoWindowDestructive`). The app keeps the pending
/// action and runs it when the window ends; this only draws it.
public struct UndoBar: View {
    public var label: String
    public var systemImage: String
    public var tint: Color
    public var started: Date
    public var duration: TimeInterval
    public var onUndo: () -> Void
    @ObservedObject private var look = NimbiAppearance.shared

    public init(label: String, systemImage: String = "checkmark.circle.fill", tint: Color = Nimbi.State.done,
                started: Date, duration: TimeInterval = Nimbi.Motion.undoWindow, onUndo: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.started = started
        self.duration = duration
        self.onUndo = onUndo
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(look.font(14)).foregroundStyle(tint)
                Text(label).font(look.font(12.5, .medium)).foregroundStyle(Nimbi.Text.primary).lineLimit(1)
                Spacer(minLength: 6)
                Button(action: onUndo) {
                    HStack(spacing: 5) {
                        KeyHint(key: "esc")
                        Text("to undo").font(look.font(11, .medium)).foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(.leading, 3).padding(.trailing, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Undo")
            }
            .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 7)
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let f = max(0, 1 - ctx.date.timeIntervalSince(started) / duration)
                GeometryReader { geo in
                    Capsule().fill(Nimbi.State.working).frame(width: geo.size.width * f, height: 2.5)
                }
                .frame(height: 2.5)
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 3)
        }
        .background(RoundedRectangle(cornerRadius: Nimbi.Radius.well, style: .continuous).fill(Nimbi.Surface.well))
    }
}
