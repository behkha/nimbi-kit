import Foundation

/// The two places on screen every nimbi app wants and only one can have (DESIGN.md 18).
public enum NimbiSurface: String, CaseIterable {
    case notch, edge
}

/// Phase 1 of the shared surfaces (DESIGN.md 18.2): an app says it wants the notch or the edge,
/// listens for other apps saying the same, and draws there only if the user picked it as the
/// surface's owner. Everyone else falls back to their menu bar glyph.
///
/// The claim travels as a distributed notification, `app.nimbi.surface.claim`, so every running
/// nimbi app hears it. The owner is a user setting kept in the `group.app.nimbi` app group's
/// defaults (standard defaults when the group isn't available), so all apps read the same answer.
public struct SurfaceClaim: Equatable {
    public var surface: NimbiSurface
    /// The claiming app, e.g. "app.nimbi.relay".
    public var bundleID: String

    public init(surface: NimbiSurface, bundleID: String = Bundle.main.bundleIdentifier ?? "") {
        self.surface = surface
        self.bundleID = bundleID
    }

    public static let notification = Notification.Name("app.nimbi.surface.claim")
    public static let appGroup = "group.app.nimbi"

    private static let surfaceKey = "surface"
    private static let bundleKey = "bundleID"

    // MARK: Claiming

    /// Tells every running nimbi app (this one included) that this app wants the surface.
    /// Posting doesn't take it: the owner setting decides who draws there.
    public func post(to center: DistributedNotificationCenter = .default()) {
        center.postNotificationName(Self.notification, object: bundleID,
                                    userInfo: [Self.surfaceKey: surface.rawValue, Self.bundleKey: bundleID],
                                    deliverImmediately: true)
    }

    /// Calls `handler` on the main queue with every claim any nimbi app posts, this one's too.
    /// Claims stop arriving when the returned observation is cancelled or released.
    public static func observe(on center: DistributedNotificationCenter = .default(),
                               _ handler: @escaping (SurfaceClaim) -> Void) -> Observation {
        let token = center.addObserver(forName: notification, object: nil, queue: .main) { note in
            guard let claim = SurfaceClaim(note) else { return }
            handler(claim)
        }
        return Observation(center: center, token: token)
    }

    /// Reads a claim back out of its notification; nil for anything malformed.
    init?(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[Self.surfaceKey] as? String, let surface = NimbiSurface(rawValue: raw),
              let bundleID = info[Self.bundleKey] as? String, !bundleID.isEmpty
        else { return nil }
        self.init(surface: surface, bundleID: bundleID)
    }

    /// A live subscription to claims. Keep it for as long as you want to hear them.
    public final class Observation {
        private let center: DistributedNotificationCenter
        private var token: NSObjectProtocol?

        init(center: DistributedNotificationCenter, token: NSObjectProtocol) {
            self.center = center
            self.token = token
        }

        public func cancel() {
            if let token { center.removeObserver(token) }
            token = nil
        }

        deinit { cancel() }
    }

    // MARK: Ownership

    /// Where every nimbi app reads and writes the owners: the app group's defaults, or standard
    /// defaults when the suite can't be opened.
    public static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    private static func ownerKey(_ surface: NimbiSurface) -> String { "surfaceOwner.\(surface.rawValue)" }

    /// The bundle ID of the app the user picked to draw on `surface`, or nil when nobody has it yet.
    public static func owner(of surface: NimbiSurface, in defaults: UserDefaults = SurfaceClaim.defaults) -> String? {
        defaults.string(forKey: ownerKey(surface))
    }

    /// Hands `surface` to `bundleID` (nil leaves it unowned). Apps hear about it through their
    /// claim observation only if the new owner posts a claim; post one after switching.
    public static func setOwner(_ bundleID: String?, of surface: NimbiSurface,
                                in defaults: UserDefaults = SurfaceClaim.defaults) {
        if let bundleID, !bundleID.isEmpty {
            defaults.set(bundleID, forKey: ownerKey(surface))
        } else {
            defaults.removeObject(forKey: ownerKey(surface))
        }
    }

    /// True when this claim's app is the surface's owner.
    public func isOwner(in defaults: UserDefaults = SurfaceClaim.defaults) -> Bool {
        Self.owner(of: surface, in: defaults) == bundleID
    }

    /// Takes the surface if nobody owns it yet (the first nimbi app wins by default), then posts
    /// the claim. Returns whether this app owns the surface afterwards.
    @discardableResult
    public func claim(in defaults: UserDefaults = SurfaceClaim.defaults,
                      center: DistributedNotificationCenter = .default()) -> Bool {
        if Self.owner(of: surface, in: defaults) == nil {
            Self.setOwner(bundleID, of: surface, in: defaults)
        }
        post(to: center)
        return isOwner(in: defaults)
    }
}
