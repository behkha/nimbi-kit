import AppKit
import Carbon

// Swiping the notch from app to app (DESIGN.md 18.6), while every app keeps drawing its own
// island: a swipe hands the notch to the next running nimbi app, which opens its island at once
// with its page drifting in from the side.

/// The nimbi apps a swipe goes through: the ones running that can be at the notch, in install
/// order. Apps with a NimbiKit island join on their first launch. Relay draws its own notch and
/// doesn't use NimbiKit's island, so it's listed here and counts while it runs with its pill set
/// to the notch; its notch itself is untouched.
@MainActor
public final class NotchRing: ObservableObject {
    public static let shared = NotchRing()

    /// Bundle IDs, in order. Updates as nimbi apps launch and quit.
    @Published public private(set) var apps: [String] = []
    /// Apps that need you right now, so their dots can glow (each island app says so itself).
    @Published public private(set) var needsYou: Set<String> = []

    /// Relay: at the notch when its pill dock setting says so.
    static let relay = "com.behkha.relay"
    private static let joinedKey = "islandApps"
    private static let needsKey = "islandNeedsYou"
    static let arrive = Notification.Name("app.nimbi.island.arrive")
    static let status = Notification.Name("app.nimbi.island.status")

    private var observers: [NSObjectProtocol] = []
    private var claims: SurfaceClaim.Observation?

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Self.status, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        // Relay's dock setting can change while it runs; a claim follows each change.
        claims = SurfaceClaim.observe { [weak self] _ in Task { @MainActor in self?.refresh() } }
        refresh()
    }

    /// Adds this app to the island apps (once, at the end: install order).
    public func join(_ bundleID: String) {
        var joined = SurfaceClaim.defaults.stringArray(forKey: Self.joinedKey) ?? []
        if !joined.contains(bundleID) {
            joined.append(bundleID)
            SurfaceClaim.defaults.set(joined, forKey: Self.joinedKey)
        }
        DistributedNotificationCenter.default().postNotificationName(Self.status, object: bundleID, userInfo: nil,
                                                                     deliverImmediately: true)
        refresh()
    }

    /// Says whether this app needs you, for its dot on the other apps' islands.
    public func setNeedsYou(_ on: Bool, for bundleID: String) {
        var set = Set(SurfaceClaim.defaults.stringArray(forKey: Self.needsKey) ?? [])
        guard set.contains(bundleID) != on else { return }
        if on { set.insert(bundleID) } else { set.remove(bundleID) }
        SurfaceClaim.defaults.set(Array(set).sorted(), forKey: Self.needsKey)
        DistributedNotificationCenter.default().postNotificationName(Self.status, object: bundleID, userInfo: nil,
                                                                     deliverImmediately: true)
        refresh()
    }

    public func refresh() {
        let joined = SurfaceClaim.defaults.stringArray(forKey: Self.joinedKey) ?? []
        var list: [String] = []
        if Self.relayAtNotch { list.append(Self.relay) }
        list += joined.filter { $0 != Self.relay && Self.isRunning($0) }
        if list != apps { apps = list }
        let needs = Set(SurfaceClaim.defaults.stringArray(forKey: Self.needsKey) ?? []).intersection(list)
        if needs != needsYou { needsYou = needs }
    }

    /// The app `step` places from `bundleID` (+1 next, −1 previous); nil past either end.
    public func neighbor(of bundleID: String?, _ step: Int) -> String? {
        guard let bundleID, let i = apps.firstIndex(of: bundleID) else { return apps.first }
        let j = i + step
        return apps.indices.contains(j) ? apps[j] : nil
    }

    /// Apps that draw their own notch without NimbiKit's island (Relay): another app watches
    /// for swipes over it.
    public func drawsItsOwn(_ bundleID: String?) -> Bool { bundleID == Self.relay }

    /// Of the running island apps, the first does the jobs only one should: watching Relay's
    /// island for swipes.
    public func isLeader(_ bundleID: String) -> Bool { apps.first { !drawsItsOwn($0) } == bundleID }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static var relayAtNotch: Bool {
        guard isRunning(relay) else { return false }
        let dock = CFPreferencesCopyAppValue("pillDock" as CFString, relay as CFString) as? String
        return dock == NimbiDock.notch.rawValue
    }

    // MARK: Handing over

    /// Gives the notch to `target`, the swipe's way of the one-click switch. Tells it first which
    /// side it's coming from, so it opens with its page drifting in, then makes it the owner.
    public static func handOff(to target: String, direction: Int, keys: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            arrive, object: target,
            userInfo: ["bundleID": target, "direction": direction, "keys": keys ? 1 : 0],
            deliverImmediately: true)
        SurfaceClaim(surface: .notch, bundleID: target).take()
    }
}

/// ⌃⌥← and ⌃⌥→ from anywhere: the notch to the previous or next app. Every island app registers
/// them and hears every press, so only the leading one (`NotchRing.isLeader`) acts on it.
@MainActor
final class RingHotkeys {
    static let shared = RingHotkeys()
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?

    private init() {}

    func register() {
        guard refs.isEmpty else { return }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard id.signature == RingHotkeys.signature else { return OSStatus(eventNotHandledErr) }
                let step = id.id == 1 ? -1 : 1
                DispatchQueue.main.async { RingHotkeys.step(step) }
                return noErr
            }, 1, &type, nil, &handler)
        }
        for (i, code) in [kVK_LeftArrow, kVK_RightArrow].enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey),
                                             EventHotKeyID(signature: Self.signature, id: UInt32(i + 1)),
                                             GetApplicationEventTarget(), 0, &ref)
            refs.append(status == noErr ? ref : nil)
        }
    }

    static let signature = OSType(0x4E52_4E47)   // 'NRNG'

    @MainActor static func step(_ step: Int) {
        let ring = NotchRing.shared
        ring.refresh()
        guard ring.isLeader(Bundle.main.bundleIdentifier ?? "") else { return }
        let owner = SurfaceClaim.owner(of: .notch)
        guard let target = ring.neighbor(of: owner, step), target != owner else { return }
        NotchRing.handOff(to: target, direction: step, keys: false)
    }
}

/// Watches for a two-finger swipe over an island this app doesn't draw (Relay's) and hands the
/// notch on. Mouse and scroll events need no permission to watch. Relay's island only opens when
/// the pointer comes to its collapsed island, so the watcher arms then, and stays armed while the
/// pointer stays over the open dashboard's area: a sideways scroll in a window under the menu bar
/// never counts.
@MainActor
final class ForeignSwipeWatcher {
    private var monitors: [Any] = []
    private var acc: CGFloat = 0
    private var armed = false
    private var lockedUntil = Date.distantPast
    private var lastEvent = Date.distantPast

    var isOn: Bool { !monitors.isEmpty }

    func start(from owner: String) {
        stop()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            Task { @MainActor in self?.scrolled(event, owner: owner) }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            Task { @MainActor in self?.moved() }
        }) { monitors.append(m) }
        moved()
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        acc = 0
        armed = false
    }

    /// The collapsed island: the notch and a wing either side.
    private static func collapsed(_ screen: NSScreen) -> NSRect {
        let (w, h) = screen.notchSize
        let wing = max(h + 4, 36) * 1.3
        return NSRect(x: screen.notchMidX - w / 2 - wing, y: screen.frame.maxY - h, width: w + 2 * wing, height: h)
    }

    /// The open dashboard, about 610 wide and 170 tall, with a little room around it.
    private static func open(_ screen: NSScreen) -> NSRect {
        NSRect(x: screen.notchMidX - 340, y: screen.frame.maxY - 200, width: 680, height: 200)
    }

    private func moved() {
        guard let screen = NSScreen.islandScreen else { armed = false; return }
        let p = NSEvent.mouseLocation
        if Self.collapsed(screen).contains(p) { armed = true }
        if !Self.open(screen).contains(p) { armed = false }
    }

    private func scrolled(_ event: NSEvent, owner: String) {
        moved()
        guard armed, event.hasPreciseScrollingDeltas else { acc = 0; return }
        let now = Date()
        if now.timeIntervalSince(lastEvent) > 0.22 { acc = 0 }
        lastEvent = now
        guard now >= lockedUntil, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        acc += Swipe.fingerDX(event)
        guard abs(acc) > Swipe.threshold else { return }
        let step = acc < 0 ? 1 : -1
        acc = 0
        lockedUntil = now.addingTimeInterval(0.22)
        let ring = NotchRing.shared
        ring.refresh()
        if let target = ring.neighbor(of: owner, step) {
            NotchRing.handOff(to: target, direction: step, keys: false)
        }
    }
}

enum Swipe {
    /// Past this much horizontal travel, a two-finger swipe moves one page (DESIGN.md 18.6).
    static let threshold: CGFloat = 46

    /// How far the fingers moved sideways, whatever the scrolling direction setting:
    /// negative to the left (the next page), positive to the right.
    static func fingerDX(_ event: NSEvent) -> CGFloat {
        event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    }
}
