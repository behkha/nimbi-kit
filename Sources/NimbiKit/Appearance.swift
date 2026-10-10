import SwiftUI

/// The two dark themes. There is no light theme.
public enum NimbiTheme: String, CaseIterable, Identifiable {
    case dark = "Dark", black = "Black"
    public var id: String { rawValue }
}

/// Where an app's pill lives on screen.
public enum NimbiDock: String, CaseIterable, Identifiable {
    case right, left, notch
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .notch: return "Notch"
        }
    }

    /// The point panels grow out of: the screen edge the pill sits on, or the top at the notch.
    public var growAnchor: UnitPoint {
        switch self {
        case .right: return .trailing
        case .left: return .leading
        case .notch: return .top
        }
    }

    public var isEdge: Bool { self != .notch }
}

/// The look settings NimbiKit's components read. The app owns and saves its settings and keeps
/// this in step with them, so the kit never touches the app's own defaults.
public final class NimbiAppearance: ObservableObject {
    public static let shared = NimbiAppearance()

    @Published public var theme: NimbiTheme = .dark
    /// 0.9 … 1.25
    @Published public var textScale: Double = 1
    /// 0.8 … 1.3
    @Published public var pillScale: Double = 1
    @Published public var dock: NimbiDock = .right
    /// Labels on the pill's buttons, on hover.
    @Published public var showTooltips = true

    private init() {}

    /// The system font at `size`, grown with the user's text size.
    public func font(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * textScale, weight: weight, design: design)
    }
}
