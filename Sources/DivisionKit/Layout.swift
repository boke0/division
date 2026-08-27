import CoreGraphics
import Foundation

/// Horizontal column layouts available per workspace.
public enum Layout: String, Codable, Equatable, Sendable, CaseIterable {
    /// Single full-screen pane.
    case full
    /// 1:1 split into two equal columns.
    case half
    /// 1:2 split (left third, right two-thirds).
    case oneTwo
    /// 2:1 split (left two-thirds, right third).
    case twoOne
    /// 1:1:1 split into three equal columns.
    case thirds

    public var paneCount: Int {
        switch self {
        case .full:
            return 1
        case .half, .oneTwo, .twoOne:
            return 2
        case .thirds:
            return 3
        }
    }

    /// Relative widths of each pane from left to right. Sums to 1.
    public var ratios: [CGFloat] {
        switch self {
        case .full:
            return [1.0]
        case .half:
            return [0.5, 0.5]
        case .oneTwo:
            return [1.0 / 3.0, 2.0 / 3.0]
        case .twoOne:
            return [2.0 / 3.0, 1.0 / 3.0]
        case .thirds:
            return [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0]
        }
    }

    public var displayName: String {
        switch self {
        case .full:
            return "1"
        case .half:
            return "1:1"
        case .oneTwo:
            return "1:2"
        case .twoOne:
            return "2:1"
        case .thirds:
            return "1:1:1"
        }
    }

    public func paneFrames(in bounds: CGRect) -> [CGRect] {
        var x = bounds.minX
        return ratios.map { ratio in
            let width = bounds.width * ratio
            let frame = CGRect(x: x, y: bounds.minY, width: width, height: bounds.height)
            x += width
            return frame
        }
    }

    /// Returns the pane whose frame contains `point`. If the point is outside all
    /// panes, the nearest pane (by horizontal distance to the pane center) is used.
    public func paneIndex(containing point: CGPoint, in bounds: CGRect) -> Int {
        let frames = paneFrames(in: bounds)
        if let index = frames.firstIndex(where: { $0.contains(point) }) {
            return index
        }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in frames.enumerated() {
            let dx = point.x - frame.midX
            let dy = point.y - frame.midY
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    public func adjacentPane(from index: Int, direction: Direction) -> Int? {
        switch direction {
        case .left:
            let next = index - 1
            return next >= 0 ? next : nil
        case .right:
            let next = index + 1
            return next < paneCount ? next : nil
        case .up, .down:
            return nil
        }
    }

    public func clampedPane(_ index: Int) -> Int {
        min(max(index, 0), paneCount - 1)
    }

    public func next() -> Layout {
        let all = Self.allCases
        let index = all.firstIndex(of: self).map { all.index(after: $0) } ?? all.startIndex
        return index == all.endIndex ? all[all.startIndex] : all[index]
    }
}

public enum Direction: String, Equatable, Sendable {
    case left
    case down
    case up
    case right
}
