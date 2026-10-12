import AppKit
import Combine
import SwiftUI

// Phase 1 of DESIGN.md 18.2, shared: who owns the notch, and an app's own island while it does.
// Skyline drew the first one; Tempo is the second app to need it, so it lives here now.

/// Who draws at the notch. An app never claims it on its own: the first nimbi app installed has
/// it by default, and the user hands it over with one click (`take`) and back (`giveBack`). Every
/// nimbi app hears the claim and moves at once.
@MainActor
public final class NotchOwnership: ObservableObject {
    @Published public private(set) var owner: String?
    /// This app's name, for "Use for Tempo".
    public let appName: String
    private let claim: SurfaceClaim
    private var observation: SurfaceClaim.Observation?
    /// Who had the notch before this app took it, to give it back to.
    private static let previousKey = "NotchPreviousOwner"

    public init(appName: String, bundleID: String = Bundle.main.bundleIdentifier ?? "") {
        self.appName = appName
        claim = SurfaceClaim(surface: .notch, bundleID: bundleID)
        owner = SurfaceClaim.owner(of: .notch)
        observation = SurfaceClaim.observe { [weak self] claim in
            guard claim.surface == .notch else { return }
            Task { @MainActor in self?.reread() }
        }
    }

    public func reread() {
        let now = SurfaceClaim.owner(of: .notch)
        if now != owner { owner = now }
    }

    public var ownedByMe: Bool { owner == claim.bundleID }

    /// The app this one would give the notch back to.
    public var previous: String? {
        UserDefaults.standard.string(forKey: Self.previousKey).flatMap { $0 == claim.bundleID ? nil : $0 }
    }

    /// The one-click switch: this app draws at the notch from now on.
    public func take() {
        if let owner, owner != claim.bundleID { UserDefaults.standard.set(owner, forKey: Self.previousKey) }
        claim.take()
        reread()
    }

    /// Back to whoever had it, or to nobody, so the next nimbi app that wants it takes it.
    public func giveBack() {
        SurfaceClaim.setOwner(previous, of: .notch)
        claim.post()
        reread()
    }

    /// "Notch is used by Relay", in words people know.
    public var line: String {
        guard let owner else { return "Notch is free." }
        if ownedByMe { return "\(appName) is in the notch." }
        return "Notch is used by \(Self.appName(owner))"
    }

    /// "Give it to Relay", or "Let it go" when nobody had it before.
    public var giveBackTitle: String { previous.map { "Give it to \(Self.appName($0))" } ?? "Let it go" }

    public static func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

/// What the island shows and how far it's open.
@MainActor
public final class IslandState: ObservableObject {
    public enum Mode: Equatable {
        /// Notch plus two wings: the cloud on the left, the glance on the right.
        case closed
        /// The page (DESIGN.md 18.7).
        case open
        /// The app's panel hangs from it: as wide as the panel, square below.
        case attached
    }

    @Published public internal(set) var mode = Mode.closed
    @Published public internal(set) var notchWidth: CGFloat = 0
    /// The menu bar's height at the notch.
    @Published public internal(set) var height: CGFloat = 32
    @Published public internal(set) var attachedWidth: CGFloat = 318

    /// Just room for the cloud and the glance: the closed island sits over the menu bar and hides
    /// the items under it, so it's narrower than 18.7's 336 pt.
    public let wing: CGFloat
    public let openWidth: CGFloat
    /// Below the notch, when open: 18.7's 150 pt band plus a little; one page needs no dots.
    public let openBand: CGFloat

    public init(wing: CGFloat = 60, openWidth: CGFloat = 580, openBand: CGFloat = 160) {
        self.wing = wing
        self.openWidth = openWidth
        self.openBand = openBand
    }

    public var closedWidth: CGFloat { notchWidth > 0 ? notchWidth + 2 * wing : 2 * wing + 8 }

    /// The island's body (ears not included) in a mode.
    public func size(_ mode: Mode, textScale: Double) -> CGSize {
        switch mode {
        case .closed: return CGSize(width: closedWidth, height: height)
        case .open: return CGSize(width: max(closedWidth, openWidth * textScale), height: height + openBand * textScale)
        case .attached: return CGSize(width: max(closedWidth, attachedWidth), height: height)
        }
    }

    /// 12 closed, 30 open, square while a panel hangs from it.
    public var bottomRadius: CGFloat {
        switch mode {
        case .closed: return 12
        case .open: return 30
        case .attached: return 0
        }
    }
}

/// An app's own island at the notch, drawn only while the user has picked this app as the notch's
/// owner, and gone the moment another nimbi app is picked. One page, so no dots and no swiping.
/// Opens after 0.2 s of hover, closes 0.6 s after the pointer leaves (DESIGN.md 18.6); a click
/// opens it at once and hands it the keyboard (`onKey`; esc closes).
@MainActor
public final class NotchIsland: NSObject {
    public let state: IslandState
    private let ownership: NotchOwnership
    private let window = IslandWindow()
    private var bag: Set<AnyCancellable> = []
    private var openTimer: Timer?
    private var closeTimer: Timer?
    private var keyMonitor: Any?
    private var moveMonitors: [Any] = []

    /// Called with true while the island is on show: the app's menu bar glyph steps aside meanwhile.
    public var onShown: ((Bool) -> Void)?
    /// Keys while the island has the keyboard (physical key codes). Return true when handled.
    public var onKey: ((UInt16) -> Bool)?

    /// `closed` draws the two wings' content, `open` the page below the notch; both get the
    /// island's state. Neither needs a background: the island is black.
    public init<Closed: View, Open: View>(ownership: NotchOwnership, state: IslandState? = nil,
                                          @ViewBuilder closed: @escaping (IslandState) -> Closed,
                                          @ViewBuilder open: @escaping (IslandState) -> Open) {
        self.ownership = ownership
        let state = state ?? IslandState()
        self.state = state
        super.init()
        let host = TrackingHostingView(rootView: IslandRoot(state: state, closed: closed, open: open))
        host.onHover = { [weak self] inside in if inside { self?.hoverIn() } }
        host.onMouseDown = { [weak self] in self?.clicked() }
        window.contentView = host

        ownership.$owner.receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &bag)
        NimbiAppearance.shared.$textScale.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.place() }
        }.store(in: &bag)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.update() }
            .store(in: &bag)
    }

    public var isShown: Bool { window.isVisible }
    public var closedWidth: CGFloat { state.closedWidth }

    /// The island's bottom edge and middle on screen, for hanging a panel below it.
    public var hangPoint: CGPoint? {
        guard isShown, let screen = NSScreen.islandScreen else { return nil }
        return CGPoint(x: screen.notchMidX, y: screen.frame.maxY - state.height)
    }

    private func update() {
        if ownership.ownedByMe, let screen = NSScreen.islandScreen {
            let (width, height) = screen.notchSize
            state.notchWidth = width
            state.height = height
            place()
            window.orderFrontRegardless()
            watchMoves(true)
            onShown?(true)
        } else {
            setMode(.closed, animated: false)
            window.orderOut(nil)
            watchMoves(false)
            onShown?(false)
        }
    }

    // MARK: Opening and closing

    /// A panel hangs from the island: it squares off at the panel's width.
    public func attach(width: CGFloat) {
        state.attachedWidth = width
        setMode(.attached)
    }

    public func detach() {
        guard state.mode == .attached else { return }
        setMode(pointerInside ? .open : .closed)
    }

    public func close() { if state.mode == .open { setMode(.closed) } }

    /// Enter events only start things: resizing the window rebuilds its tracking area and sends
    /// stray exits, so leaving is judged by where the pointer is.
    private func hoverIn() {
        guard state.mode == .closed else { return }
        openTimer?.invalidate()
        openTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pointerInside else { return }
                self.setMode(.open)
            }
        }
    }

    private var pointerInside: Bool { window.frame.contains(NSEvent.mouseLocation) }

    /// A freshly shown island's tracking area doesn't always report the first entry, so pointer
    /// moves over the closed island count as hovering too. Mouse moves need no permission.
    private func watchMoves(_ on: Bool) {
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors = []
        guard on else { return }
        let check: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.mode == .closed, self.openTimer?.isValid != true, self.pointerInside else { return }
                self.hoverIn()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: check) { moveMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { check($0); return $0 }) {
            moveMonitors.append(local)
        }
    }

    /// While open, checks the pointer ten times a second and closes once it has been away 0.6 s.
    private func watchPointer() {
        guard closeTimer == nil else { return }
        var awaySince: Date?
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                guard self.state.mode == .open else { timer.invalidate(); self.closeTimer = nil; return }
                if self.pointerInside { awaySince = nil; return }
                let since = awaySince ?? Date()
                awaySince = since
                if Date().timeIntervalSince(since) >= 0.6 {
                    timer.invalidate()
                    self.closeTimer = nil
                    self.setMode(.closed)
                }
            }
        }
    }

    private func clicked() {
        guard state.mode != .attached else { return }
        openTimer?.invalidate()
        if state.mode == .closed { setMode(.open) }
        // A click is an invitation to use the keys.
        window.makeKey()
        startKeys()
    }

    private func setMode(_ mode: IslandState.Mode, animated: Bool = true) {
        guard mode != state.mode else { place(); return }
        let growing = area(mode) > area(state.mode)
        // Grow the window first and the shape inside it, or shrink the shape first and the window after.
        if growing { place(for: mode) }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(animated ? (reduce ? .easeOut(duration: 0.15) : (growing ? Nimbi.Motion.islandOpen : Nimbi.Motion.islandClose)) : nil) {
            state.mode = mode
        }
        if mode == .open { watchPointer() } else { stopKeys() }
        if !growing {
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.45 : 0)) { [weak self] in
                guard let self, self.state.mode == mode else { return }
                self.place(for: mode)
            }
        }
    }

    private func area(_ mode: IslandState.Mode) -> CGFloat {
        let s = state.size(mode, textScale: NimbiAppearance.shared.textScale)
        return s.width * s.height
    }

    private func place(for mode: IslandState.Mode? = nil) {
        guard let screen = NSScreen.islandScreen else { return }
        let size = state.size(mode ?? state.mode, textScale: NimbiAppearance.shared.textScale)
        let width = size.width + 2 * IslandShape.defaultEar
        window.setFrame(NSRect(x: (screen.notchMidX - width / 2).rounded(), y: screen.frame.maxY - size.height,
                               width: width, height: size.height), display: true)
    }

    // MARK: Keys

    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if event.keyCode == 53 { self.setMode(.closed); return nil }   // esc
            return self.onKey?(event.keyCode) == true ? nil : event
        }
    }

    private func stopKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// Borderless, above the menu bar, on every space, and never activating its app.
public final class IslandWindow: NSPanel {
    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    public init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    /// The island sits in the menu bar; don't let AppKit push it down below it.
    override public func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting view with hover that works while its app isn't active, and a click hook.
public final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    public var onHover: ((Bool) -> Void)?
    public var onMouseDown: (() -> Void)?
    private var area: NSTrackingArea?

    public required init(rootView: Content) { super.init(rootView: rootView) }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override public func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); onHover?(true) }
    override public func mouseExited(with event: NSEvent) { super.mouseExited(with: event); onHover?(false) }
    override public func mouseDown(with event: NSEvent) { onMouseDown?(); super.mouseDown(with: event) }
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The black island, growing and shrinking with its mode, with the app's content in it.
private struct IslandRoot<Closed: View, Open: View>: View {
    @ObservedObject var state: IslandState
    var closed: (IslandState) -> Closed
    var open: (IslandState) -> Open
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        let size = state.size(state.mode, textScale: look.textScale)
        ZStack(alignment: .top) {
            IslandShape(bottomRadius: state.bottomRadius)
                .fill(Color.black)
            if state.mode == .open {
                open(state)
                    .padding(.top, state.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.08)))
            } else {
                closed(state)
                    .frame(height: state.height)
                    .padding(.horizontal, IslandShape.defaultEar)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: size.width + 2 * IslandShape.defaultEar, height: size.height)
        // The page grows with the island; nothing may spill past its edge on the way.
        .clipShape(IslandShape(bottomRadius: state.bottomRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// The closed island's two wings around the notch: the cloud on the left, the glance on the right.
public struct IslandWings<Left: View, Right: View>: View {
    @ObservedObject var state: IslandState
    var left: Left
    var right: Right

    public init(state: IslandState, @ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.state = state
        self.left = left()
        self.right = right()
    }

    public var body: some View {
        HStack(spacing: 0) {
            left.frame(width: state.wing, alignment: .center)
            Spacer(minLength: state.notchWidth)
            right.frame(width: state.wing, alignment: .center)
        }
    }
}
