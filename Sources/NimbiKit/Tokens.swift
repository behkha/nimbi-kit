import SwiftUI

/// nimbi design tokens. Mirror of DESIGN.md (sections 4, 6.1 and 9.2); keep the two in sync.
public enum Nimbi {
    public enum Surface {
        /// The notch island, the Black theme's ground.
        public static let void = Color(hex: "#000000")
        /// Panel fill in the Black theme.
        public static let panelBlack = Color(hex: "#090909")
        /// Floating panels (card, lists, menus) in the Dark theme.
        public static let panel = Color(hex: "#141414")
        public static let window = Color(hex: "#0E0E10")
        public static let sidebar = Color(hex: "#0A0A0B")
        public static let column = Color(hex: "#111113")
        /// The edge pill before macOS 26, and while it's active.
        public static let pill = Color(hex: "#111112")
        public static let pillActive = Color(hex: "#2C2C2E")
        public static let sliver = Color(hex: "#080808")
        public static let tooltipIsland = Color(hex: "#1C1C1E")
        public static let well = Color.white.opacity(0.05)
        public static let row = Color.white.opacity(0.055)
        public static let codeWell = Color.black.opacity(0.45)
    }

    public enum Line {
        public static let rim = Color.white.opacity(0.09)      // 0.75 pt
        public static let row = Color.white.opacity(0.07)      // 1 pt
        public static let card = Color.white.opacity(0.08)
        public static let pill = Color.white.opacity(0.14)     // 1 pt
        public static let pillActive = Color.white.opacity(0.24)
    }

    public enum Text {
        public static let primary = Color.white
        public static let message = Color.white.opacity(0.92)
        public static let strong = Color.white.opacity(0.88)
        public static let dim = Color.white.opacity(0.55)
        public static let faint = Color.white.opacity(0.38)
        /// Header subtitles only.
        public static let ghost = Color.white.opacity(0.32)
    }

    /// The cloud's light. Only on the cloud, the wordmark and one hero word on the web.
    public enum Aurora {
        public static let sky = Color(hex: "#7FD0FF")
        public static let lavender = Color(hex: "#B9B4FF")
        public static let blush = Color(hex: "#F3B6EC")
        /// The resting glow, also used for focus rings.
        public static let glow = Color(hex: "#B07CFF")
        /// Eyes, and text set on aurora.
        public static let ink = Color(hex: "#24163A")
        public static let gradient = LinearGradient(colors: [sky, lavender, blush],
                                                    startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    /// Color means state, never "click me".
    public enum State {
        public static let working = Color(hex: "#0A84FF")
        public static let waiting = Color(hex: "#F2B33D")
        public static let done = Color(hex: "#30D158")
        public static let destructive = Color(hex: "#FF6961")
        public static let asking = Color(hex: "#FFD426")
        public static let listening = Color(hex: "#FF4F5E")
        public static let selectedFill = Color(hex: "#143A20")
        public static let selectedBorder = Color(hex: "#30D158").opacity(0.55)
        public static let promptBubble = Color(hex: "#13467E")
        public static let agentBubble = Color(hex: "#262626")
        /// Only when representing Claude itself.
        public static let claude = Color(hex: "#D97757")
    }

    /// Anything running hot. Gradients run yellow → orange → red.
    public enum Heat {
        public static let core = Color(hex: "#FFF2B0")
        public static let yellow = Color(hex: "#FFC93C")
        public static let orange = Color(hex: "#FF7A1A")
        public static let red = Color(hex: "#E8332A")
        public static let ember = Color(hex: "#8E1B12")
        public static let coal = Color(hex: "#2A0E0A")
    }

    /// Continuous (squircle) corners. Buttons, chips, toasts, tooltips and fields are capsules.
    public enum Radius {
        public static let keyHint: CGFloat = 5, iconTile: CGFloat = 7, menuRow: CGFloat = 8
        public static let row: CGFloat = 9, choice: CGFloat = 10, group: CGFloat = 11, well: CGFloat = 12
        public static let bubble: CGFloat = 14, settings: CGFloat = 16, panel: CGFloat = 18, card: CGFloat = 20
    }

    public enum Motion {
        public static let enter = Animation.spring(response: 0.42, dampingFraction: 0.8)
        public static let bounce = Animation.spring(response: 0.55, dampingFraction: 0.56).delay(0.06)
        public static let press = Animation.spring(response: 0.2, dampingFraction: 0.7)
        public static let panel = Animation.spring(response: 0.34, dampingFraction: 0.8)
        public static let islandOpen = Animation.spring(response: 0.5, dampingFraction: 0.7)
        public static let islandClose = Animation.spring(response: 0.38, dampingFraction: 0.9)
        public static let mood = Animation.spring(response: 0.45, dampingFraction: 0.55)
        public static let gaze = Animation.spring(response: 0.5, dampingFraction: 0.78)
        public static let leave = Animation.easeIn(duration: 0.2)
        public static let hover = Animation.easeOut(duration: 0.12)
        public static let swap = Animation.easeOut(duration: 0.16)
        public static let undoWindow: TimeInterval = 2.0
        public static let undoWindowDestructive: TimeInterval = 2.5
    }
}

extension Color {
    /// "#RRGGBB" (the "#" is optional) in sRGB. Anything else comes out mid grey.
    public init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        } else {
            r = 0.6; g = 0.6; b = 0.6
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// SwiftUI's `@State` is a macro in this SDK and its plugin only ships with full Xcode.
/// Using the property wrapper through an alias builds with the Command Line Tools alone.
typealias ViewState<Value> = SwiftUI.State<Value>
