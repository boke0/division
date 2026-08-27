import CoreGraphics
import Testing
@testable import DivisionKit

private let leftScreen = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let rightScreen = CGRect(x: 1000, y: 0, width: 1200, height: 800)
private let farRightScreen = CGRect(x: 2200, y: 0, width: 800, height: 800)
private let aboveScreen = CGRect(x: 0, y: 800, width: 1000, height: 600)
private let diagonalUpRight = CGRect(x: 1000, y: 800, width: 1000, height: 600)

@Test func adjacentFrameIndexLeftRight() {
    let frames = [leftScreen, rightScreen]
    #expect(adjacentFrameIndex(from: rightScreen, among: frames, direction: .left) == 0)
    #expect(adjacentFrameIndex(from: leftScreen, among: frames, direction: .right) == 1)
    #expect(adjacentFrameIndex(from: leftScreen, among: frames, direction: .left) == nil)
    #expect(adjacentFrameIndex(from: rightScreen, among: frames, direction: .right) == nil)
}

@Test func adjacentFrameIndexUpDown() {
    let frames = [leftScreen, aboveScreen]
    #expect(adjacentFrameIndex(from: leftScreen, among: frames, direction: .up) == 1)
    #expect(adjacentFrameIndex(from: aboveScreen, among: frames, direction: .down) == 0)
    #expect(adjacentFrameIndex(from: leftScreen, among: frames, direction: .down) == nil)
}

@Test func adjacentFrameIndexPicksNearestNotFarthest() {
    let frames = [leftScreen, rightScreen, farRightScreen]
    #expect(adjacentFrameIndex(from: leftScreen, among: frames, direction: .right) == 1)
    #expect(adjacentFrameIndex(from: farRightScreen, among: frames, direction: .left) == 1)
}

@Test func adjacentFrameIndexDiagonalPrefersHorizontal() {
    let frames = [leftScreen, diagonalUpRight]
    #expect(adjacentFrameIndex(from: leftScreen, among: frames, direction: .right) == 1)
    #expect(adjacentFrameIndex(from: leftScreen, among: frames, direction: .up) == nil)
}

@Test func adjacentFrameIndexIgnoresSelfAndEmpty() {
    #expect(adjacentFrameIndex(from: leftScreen, among: [leftScreen], direction: .right) == nil)
    #expect(adjacentFrameIndex(from: leftScreen, among: [], direction: .left) == nil)
}

@Test func landingPaneHorizontalUsesOppositeEdge() {
    #expect(
        landingPane(
            direction: .left,
            sourceLayout: .full,
            sourcePane: 0,
            destinationLayout: .thirds
        ) == 2
    )
    #expect(
        landingPane(
            direction: .right,
            sourceLayout: .thirds,
            sourcePane: 2,
            destinationLayout: .half
        ) == 0
    )
    #expect(
        landingPane(
            direction: .left,
            sourceLayout: .half,
            sourcePane: 0,
            destinationLayout: .full
        ) == 0
    )
}

@Test func landingPaneVerticalUsesSourceRatioMidpoint() {
    #expect(
        landingPane(
            direction: .up,
            sourceLayout: .thirds,
            sourcePane: 2,
            destinationLayout: .half
        ) == 1
    )
    #expect(
        landingPane(
            direction: .down,
            sourceLayout: .thirds,
            sourcePane: 0,
            destinationLayout: .half
        ) == 0
    )
    #expect(
        landingPane(
            direction: .up,
            sourceLayout: .half,
            sourcePane: 1,
            destinationLayout: .full
        ) == 0
    )
}

@Test func resolveNavigationTargetPrefersAdjacentPane() {
    #expect(
        resolveNavigationTarget(
            fromPane: 0,
            layout: .half,
            direction: .right,
            neighborLayout: .thirds
        ) == .pane(1)
    )
}

@Test func resolveNavigationTargetFallsBackToNeighbor() {
    #expect(
        resolveNavigationTarget(
            fromPane: 0,
            layout: .half,
            direction: .left,
            neighborLayout: .thirds
        ) == .neighbor(pane: 2)
    )
    #expect(
        resolveNavigationTarget(
            fromPane: 0,
            layout: .full,
            direction: .right,
            neighborLayout: .half
        ) == .neighbor(pane: 0)
    )
}

@Test func resolveNavigationTargetNilWithoutNeighbor() {
    #expect(
        resolveNavigationTarget(
            fromPane: 0,
            layout: .half,
            direction: .left,
            neighborLayout: nil
        ) == nil
    )
    #expect(
        resolveNavigationTarget(
            fromPane: 0,
            layout: .half,
            direction: .up,
            neighborLayout: nil
        ) == nil
    )
}
