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

    public var bundleID: String { claim.bundleID }

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
    /// Where the page is in a swipe (DESIGN.md 18.8's offset): 0 in place, −1 gone left, 1 waiting
    /// on the right. Pages read it through `.islandDrift(_:)`.
    @Published public internal(set) var drift: CGFloat = 0
    /// The apps a swipe goes through (`NotchRing`), and this app's bundle ID among them.
    @Published public internal(set) var ring: [String] = []
    @Published public internal(set) var needsYou: Set<String> = []
    public internal(set) var me = ""

    /// Just room for the cloud and the glance: the closed island sits over the menu bar and hides
    /// the items under it, so it's narrower than 18.7's 336 pt.
    public let wing: CGFloat
    public let openWidth: CGFloat
    /// Below the notch, when open: 18.7's 150 pt band plus a little, without the page dots.
    public let openBand: CGFloat
    /// Room for the page dots, 12 pt from the bottom, when there's more than one app to swipe to.
    public static let dotsBand: CGFloat = 16

    public init(wing: CGFloat = 60, openWidth: CGFloat = 580, openBand: CGFloat = 160) {
        self.wing = wing
        self.openWidth = openWidth
        self.openBand = openBand
    }

    /// Page dots show once there's another app to swipe to.
    public var showsDots: Bool { ring.count > 1 && ring.contains(me) }

    public var closedWidth: CGFloat { notchWidth > 0 ? notchWidth + 2 * wing : 2 * wing + 8 }

    /// The island's body (ears not included) in a mode.
    public func size(_ mode: Mode, textScale: Double) -> CGSize {
        switch mode {
        case .closed: return CGSize(width: closedWidth, height: height)
        case .open:
            return CGSize(width: max(closedWidth, openWidth * textScale),
                          height: height + openBand * textScale + (showsDots ? Self.dotsBand : 0))
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
/// owner, and gone the moment another nimbi app is picked. Opens after 0.2 s of hover, closes
/// 0.6 s after the pointer leaves (DESIGN.md 18.6); a click opens it at once and hands it the
/// keyboard (`onKey`; esc closes, ← → change app).
///
/// Swiping (18.6): a two-finger swipe, a drag or ← → on the open island hands the notch to the
/// next running nimbi app (`NotchRing`), whose island opens with its page drifting in. Every app
/// keeps drawing its own island; the swipe only moves the notch between them.
@MainActor
public final class NotchIsland: NSObject {
    public let state: IslandState
    private let ownership: NotchOwnership
    private let ring = NotchRing.shared
    private let window = IslandWindow()
    private var bag: Set<AnyCancellable> = []
    private var openTimer: Timer?
    private var closeTimer: Timer?
    private var keyMonitor: Any?
    private var moveMonitors: [Any] = []
    private var scrollMonitor: Any?
    private var arrivals: NSObjectProtocol?
    private let foreign = ForeignSwipeWatcher()

    /// A swipe in progress: horizontal travel so far, and when it last moved.
    private var swipeTravel: CGFloat = 0
    private var swipeLast = Date.distantPast
    private var swipeLockedUntil = Date.distantPast
    /// Set while this app hands the notch on, so its island lingers under the next one.
    private var handingOff = false
    /// The side the next owner's page should drift in from, when it arrives.
    private var arrival: (direction: Int, keys: Bool, at: Date)?
    private var hasKeys: Bool { keyMonitor != nil }
    /// The last two drag samples (travel, time), for the release speed.
    private var dragSamples: [(CGFloat, Date)] = []

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
        state.me = ownership.bundleID
        super.init()
        var actions = IslandRootActions()
        let host = TrackingHostingView(rootView: IslandRoot(state: state, closed: closed, open: open, actions: actions))
        host.onHover = { [weak self] inside in if inside { self?.hoverIn() } }
        host.onMouseDown = { [weak self] in self?.clicked() }
        window.contentView = host
        actions.drag = { [weak self] dx, ended in self?.dragged(dx, ended: ended) }
        actions.jump = { [weak self] target in self?.jump(to: target) }
        host.rootView = IslandRoot(state: state, closed: closed, open: open, actions: actions)

        ring.join(ownership.bundleID)
        RingHotkeys.shared.register()
        ring.$apps.combineLatest(ring.$needsYou).receive(on: RunLoop.main).sink { [weak self] apps, needs in
            guard let self else { return }
            let dotsBefore = self.state.showsDots
            self.state.ring = apps
            self.state.needsYou = needs
            if dotsBefore != self.state.showsDots { self.place() }
            self.watchForeign()
        }.store(in: &bag)
        arrivals = DistributedNotificationCenter.default().addObserver(forName: NotchRing.arrive, object: nil, queue: .main) { [weak self] note in
            guard let info = note.userInfo, let target = info["bundleID"] as? String else { return }
            let direction = info["direction"] as? Int ?? 1
            let keys = (info["keys"] as? Int ?? 0) == 1
            Task { @MainActor in
                guard let self, target == self.ownership.bundleID else { return }
                self.arrival = (direction, keys, Date())
                if self.ownership.ownedByMe, self.isShown { self.arrive() }
            }
        }

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

    /// Tells the other apps' islands whether this app needs you (their dot for it glows amber).
    public func setNeedsYou(_ on: Bool) { ring.setNeedsYou(on, for: ownership.bundleID) }

    private func update() {
        DispatchQueue.main.async { [weak self] in self?.watchForeign() }
        if ownership.ownedByMe, let screen = NSScreen.islandScreen {
            let (width, height) = screen.notchSize
            state.notchWidth = width
            state.height = height
            handingOff = false
            if let a = arrival, Date().timeIntervalSince(a.at) < 2 {
                arrive()
            } else {
                place()
                window.orderFrontRegardless()
            }
            watchMoves(true)
            onShown?(true)
        } else {
            watchMoves(false)
            stopScroll()
            stopKeys()
            let hide = { [weak self] in
                guard let self, !self.ownership.ownedByMe else { return }
                self.state.mode = .closed
                self.state.drift = 0
                self.window.orderOut(nil)
                self.onShown?(false)
            }
            // Handing on: stay a moment, so the next island opens over this one, not over a gap.
            if handingOff {
                handingOff = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { hide() }
            } else {
                hide()
            }
        }
    }

    /// Arrived by a swipe: open at once, the page drifting in from the side it came from.
    private func arrive() {
        guard let a = arrival else { return }
        arrival = nil
        openTimer?.invalidate()
        state.drift = CGFloat(a.direction) * 0.85
        state.mode = .open
        place(for: .open)
        window.orderFrontRegardless()
        watchPointer()
        startScroll()
        if a.keys { window.makeKey(); startKeys() }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduce ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.8)) {
            state.drift = 0
        }
    }

    // MARK: Swiping

    /// The next (+1) or previous (−1) app: the page drifts out, then the notch goes to that app.
    /// At either end the page only stretches and springs back.
    private func move(_ step: Int) {
        ring.refresh()
        guard let target = ring.neighbor(of: ownership.bundleID, step), target != ownership.bundleID else {
            bounce(step)
            return
        }
        let keys = hasKeys
        withAnimation(.easeIn(duration: 0.16)) { state.drift = CGFloat(-step) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self else { return }
            self.handingOff = true
            NotchRing.handOff(to: target, direction: step, keys: keys)
        }
    }

    private func jump(to target: String) {
        guard let from = state.ring.firstIndex(of: ownership.bundleID), let to = state.ring.firstIndex(of: target),
              from != to else { return }
        let step = to > from ? 1 : -1
        withAnimation(.easeIn(duration: 0.16)) { state.drift = CGFloat(-step) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            self?.handingOff = true
            NotchRing.handOff(to: target, direction: step, keys: false)
        }
    }

    private func bounce(_ step: Int) {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) { state.drift = CGFloat(-step) * 0.12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { self?.state.drift = 0 }
        }
    }

    /// Mouse drags (18.6): the page follows the pointer, stretching at the ends; on release it
    /// commits past 18% of the width or 0.45 pt/ms, or springs back.
    private func dragged(_ dx: CGFloat, ended: Bool) {
        guard state.mode == .open else { return }
        let now = Date()
        if !ended { dragSamples = Array((dragSamples + [(dx, now)]).suffix(2)) }
        var velocity: CGFloat = 0
        if ended, let first = dragSamples.first, let last = dragSamples.last, last.1 > first.1 {
            // pt/ms over the last stretch, and nothing if the pointer stopped before letting go.
            velocity = now.timeIntervalSince(last.1) < 0.08 ? (last.0 - first.0) / CGFloat(last.1.timeIntervalSince(first.1) * 1000) : 0
        }
        if ended { dragSamples = [] }
        let width = state.size(.open, textScale: NimbiAppearance.shared.textScale).width
        let step = dx < 0 ? 1 : -1
        let free = ring.neighbor(of: ownership.bundleID, step) != nil
        if !ended {
            let o = dx / (0.55 * width)
            state.drift = free ? o : o * 0.3
            return
        }
        if free && (abs(dx) > 0.18 * width || abs(velocity) > 0.45) {
            move(step)
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { state.drift = 0 }
        }
    }

    /// Two-finger swipes over the open island: past 46 pt, one app; then quiet for 220 ms first.
    private func startScroll() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window, self.state.mode == .open, event.hasPreciseScrollingDeltas
            else { return event }
            let now = Date()
            if now.timeIntervalSince(self.swipeLast) > 0.22 { self.swipeTravel = 0 }
            self.swipeLast = now
            guard now >= self.swipeLockedUntil, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            self.swipeTravel += Swipe.fingerDX(event)
            if abs(self.swipeTravel) > Swipe.threshold {
                let step = self.swipeTravel < 0 ? 1 : -1
                self.swipeTravel = 0
                self.swipeLockedUntil = now.addingTimeInterval(0.22)
                self.move(step)
            } else if event.phase == .ended || event.momentumPhase == .began {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { self.state.drift = 0 }
            } else {
                // A little give while the fingers move, so the page feels attached to them.
                let width = self.state.size(.open, textScale: NimbiAppearance.shared.textScale).width
                self.state.drift = self.swipeTravel / (0.55 * width) * 0.6
            }
            return nil
        }
    }

    private func stopScroll() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        swipeTravel = 0
    }

    /// While an app that draws its own notch (Relay) has it, the leading island app watches for
    /// swipes over it, so Relay's island takes part without changing.
    private func watchForeign() {
        let owner = ownership.owner
        if ring.drawsItsOwn(owner), let owner, ring.isLeader(ownership.bundleID), ring.apps.count > 1 {
            if !foreign.isOn { foreign.start(from: owner) }
        } else if foreign.isOn {
            foreign.stop()
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
                if self.pointerInside || self.hasKeys { awaySince = nil; return }
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
            state.drift = 0
        }
        if mode == .open { watchPointer(); startScroll() } else { stopKeys(); stopScroll() }
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
            switch event.keyCode {
            case 53: self.setMode(.closed); return nil      // esc
            case 123: self.move(-1); return nil              // ←
            case 124: self.move(1); return nil               // →
            default: return self.onKey?(event.keyCode) == true ? nil : event
            }
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

struct IslandRootActions {
    /// Drag travel (pt), and whether it ended.
    var drag: (CGFloat, Bool) -> Void = { _, _ in }
    /// A page dot: the notch to that app.
    var jump: (String) -> Void = { _ in }
}

/// The black island, growing and shrinking with its mode, with the app's content in it.
private struct IslandRoot<Closed: View, Open: View>: View {
    @ObservedObject var state: IslandState
    var closed: (IslandState) -> Closed
    var open: (IslandState) -> Open
    var actions: IslandRootActions
    @ObservedObject private var look = NimbiAppearance.shared

    var body: some View {
        let size = state.size(state.mode, textScale: look.textScale)
        let o = state.drift
        ZStack(alignment: .top) {
            IslandShape(bottomRadius: state.bottomRadius)
                .fill(Color.black)
            if state.mode == .open {
                // Drift (DESIGN.md 18.8): the page slides and fades; its cloud and text add their own.
                open(state)
                    .padding(.top, state.height)
                    .padding(.bottom, state.showsDots ? IslandState.dotsBand : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: o * 0.55 * size.width)
                    .opacity(Double(max(0, 1 - 1.15 * abs(o))))
                    .environment(\.islandDrift, IslandDrift(offset: o, width: size.width))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { actions.drag($0.translation.width, false) }
                        .onEnded { actions.drag($0.translation.width, true) })
                    .transition(.opacity.animation(.easeOut(duration: 0.18).delay(0.08)))
                if state.showsDots {
                    PageDots(state: state, jump: actions.jump)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
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

/// One dot per app (18.7): the current one a 16 × 6 white capsule, the others 6 pt at white
/// 0.28, and one that needs you amber, glowing and pulsing. Each is a tab with the app's name.
private struct PageDots: View {
    @ObservedObject var state: IslandState
    var jump: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(state.ring, id: \.self) { app in
                let current = app == state.me
                let urgent = !current && state.needsYou.contains(app)
                Button { jump(app) } label: {
                    Capsule()
                        .fill(current ? Color.white : urgent ? Nimbi.State.asking : Color.white.opacity(0.28))
                        .frame(width: current ? 16 : 6, height: 6)
                        .shadow(color: urgent ? Nimbi.State.asking.opacity(0.8) : .clear, radius: 4)
                        .modifier(Pulse(on: urgent))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(NotchOwnership.appName(app))
                .accessibilityLabel(NotchOwnership.appName(app) + (urgent ? ", needs you" : ""))
                .accessibilityAddTraits(current ? [.isSelected] : [])
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.ring)
    }
}

private struct Pulse: ViewModifier {
    var on: Bool
    @ViewState private var big = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on && big ? 1.35 : 1)
            .onAppear { animate() }
            .onChange(of: on) { _ in animate() }
    }

    private func animate() {
        guard on else { big = false; return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { big = true }
    }
}

/// Where a page is in a swipe, for its layers.
public struct IslandDrift: Equatable {
    public var offset: CGFloat
    public var width: CGFloat
}

private struct IslandDriftKey: EnvironmentKey {
    static let defaultValue = IslandDrift(offset: 0, width: 580)
}

extension EnvironmentValues {
    public var islandDrift: IslandDrift {
        get { self[IslandDriftKey.self] }
        set { self[IslandDriftKey.self] = newValue }
    }
}

/// The layers of a page in a swipe (DESIGN.md 18.8): the cloud moves furthest, lifts and
/// shrinks a little; the text moves a little more than the page.
public enum IslandDriftLayer { case cloud, text }

private struct DriftLayer: ViewModifier {
    var layer: IslandDriftLayer
    @Environment(\.islandDrift) private var drift

    func body(content: Content) -> some View {
        let o = drift.offset, a = abs(o)
        switch layer {
        case .cloud:
            content
                .scaleEffect(1 - 0.18 * a)
                .offset(x: o * 0.5 * drift.width, y: -10 * a)
        case .text:
            content.offset(x: o * 0.15 * drift.width)
        }
    }
}

extension View {
    /// Moves this part of an island page with the swipe: `.cloud` for the page's cloud, `.text`
    /// for its words.
    public func islandDrift(_ layer: IslandDriftLayer) -> some View { modifier(DriftLayer(layer: layer)) }
}

/// The closed island's two wings around the notch: the cloud on the left, the glance on the
/// right, with 4 pt dots under the glance when there are other apps to swipe to.
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
            VStack(spacing: 2) {
                right
                if state.showsDots {
                    HStack(spacing: 3) {
                        ForEach(state.ring, id: \.self) { app in
                            Circle()
                                .fill(app == state.me ? Color.white
                                      : state.needsYou.contains(app) ? Nimbi.State.asking : Color.white.opacity(0.3))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(width: state.wing, alignment: .center)
        }
    }
}
