import AppKit
import SwiftUI

// MARK: - The notch island's outline and the screen's notch

/// The notch island (DESIGN.md 18.7): flat along the top of the screen, flaring into the bezel
/// at both top corners with concave ears, and rounded below, like the camera housing it grows
/// out of. `rect` includes the ears (`ear` on each side).
public struct IslandShape: Shape {
    public var bottomRadius: CGFloat
    public var ear: CGFloat

    /// The concave flare where the island's top meets the bezel, on each side.
    public static let defaultEar: CGFloat = 7

    public init(bottomRadius: CGFloat, ear: CGFloat = IslandShape.defaultEar) {
        self.bottomRadius = bottomRadius
        self.ear = ear
    }

    public var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let left = rect.minX + ear, right = rect.maxX - ear
        let e = min(ear, rect.height / 2)
        let r = max(0, min(bottomRadius, (right - left) / 2, rect.height - e))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: left, y: rect.minY + e), control: CGPoint(x: left, y: rect.minY))
        p.addLine(to: CGPoint(x: left, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: left + r, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        p.addLine(to: CGPoint(x: right - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - r), control: CGPoint(x: right, y: rect.maxY))
        p.addLine(to: CGPoint(x: right, y: rect.minY + e))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

extension NSScreen {
    /// True on a screen with a camera housing.
    public var hasNotch: Bool { safeAreaInsets.top > 0 }

    /// The camera housing's width and height in points, or (0, menu bar height) without one.
    public var notchSize: (CGFloat, CGFloat) {
        if hasNotch, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            return (max(0, frame.width - left.width - right.width), safeAreaInsets.top)
        }
        let menuBar = frame.maxY - visibleFrame.maxY
        return (0, menuBar > 10 ? menuBar : 24)
    }

    /// The middle of the camera housing (the screen's middle without one).
    public var notchMidX: CGFloat {
        if hasNotch, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            return frame.minX + left.width + (frame.width - left.width - right.width) / 2
        }
        return frame.midX
    }

    /// The screen the island belongs on: the first one with a notch, else the main screen.
    public static var islandScreen: NSScreen? {
        screens.first(where: \.hasNotch) ?? main ?? screens.first
    }
}
