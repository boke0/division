import CoreGraphics
import Foundation

/// Where directional focus/move should land after resolving adjacent panes and
/// an optional neighboring display layout.
public enum NavigationTarget: Equatable, Sendable {
    /// Adjacent pane on the current space.
    case pane(Int)
    /// Landing pane on a neighboring display's current space.
    case neighbor(pane: Int)
}

/// Index of the closest frame whose center lies primarily in `direction`
/// from `current`'s center. Frames equal to `current` are ignored.
///
/// Frames are Cocoa-style (origin bottom-left, y increases upward), matching
/// `NSScreen.frame`. Horizontal directions win exact 45-degree diagonals.
public func adjacentFrameIndex(
    from current: CGRect,
    among frames: [CGRect],
    direction: Direction
) -> Int? {
    let origin = CGPoint(x: current.midX, y: current.midY)
    var best: Int?
    var bestDistance = CGFloat.greatestFiniteMagnitude
    for (index, frame) in frames.enumerated() where frame != current {
        let dx = frame.midX - origin.x
        let dy = frame.midY - origin.y
        guard isPrimaryComponent(dx: dx, dy: dy, direction: direction) else {
            continue
        }
        let distance = dx * dx + dy * dy
        if distance < bestDistance {
            bestDistance = distance
            best = index
        }
    }
    return best
}

/// Pane on `destinationLayout` that directional movement from `sourcePane` lands on.
public func landingPane(
    direction: Direction,
    sourceLayout: Layout,
    sourcePane: Int,
    destinationLayout: Layout
) -> Int {
    switch direction {
    case .left:
        return destinationLayout.paneCount - 1
    case .right:
        return 0
    case .up, .down:
        let ratio = paneRatioMidpoint(layout: sourceLayout, pane: sourcePane)
        return paneIndex(layout: destinationLayout, containingRatio: ratio)
    }
}

/// Adjacent pane on `layout` if one exists; otherwise the landing pane of
/// `neighborLayout` when a neighbor display is present.
public func resolveNavigationTarget(
    fromPane: Int,
    layout: Layout,
    direction: Direction,
    neighborLayout: Layout?
) -> NavigationTarget? {
    if let adjacent = layout.adjacentPane(from: fromPane, direction: direction) {
        return .pane(adjacent)
    }
    guard let neighborLayout else {
        return nil
    }
    return .neighbor(
        pane: landingPane(
            direction: direction,
            sourceLayout: layout,
            sourcePane: fromPane,
            destinationLayout: neighborLayout
        )
    )
}

private func isPrimaryComponent(dx: CGFloat, dy: CGFloat, direction: Direction) -> Bool {
    switch direction {
    case .left:
        return dx < 0 && abs(dx) >= abs(dy)
    case .right:
        return dx > 0 && abs(dx) >= abs(dy)
    case .up:
        return dy > 0 && abs(dy) > abs(dx)
    case .down:
        return dy < 0 && abs(dy) > abs(dx)
    }
}

private func paneRatioMidpoint(layout: Layout, pane: Int) -> CGFloat {
    let pane = layout.clampedPane(pane)
    let start = layout.ratios.prefix(pane).reduce(CGFloat(0), +)
    return start + layout.ratios[pane] / 2
}

private func paneIndex(layout: Layout, containingRatio ratio: CGFloat) -> Int {
    var x: CGFloat = 0
    for (index, width) in layout.ratios.enumerated() {
        x += width
        if ratio < x || index == layout.ratios.count - 1 {
            return index
        }
    }
    return layout.paneCount - 1
}
