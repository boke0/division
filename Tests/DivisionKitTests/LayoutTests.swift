import CoreGraphics
import Testing
@testable import DivisionKit

@Test func paneCounts() {
    #expect(Layout.full.paneCount == 1)
    #expect(Layout.half.paneCount == 2)
    #expect(Layout.oneTwo.paneCount == 2)
    #expect(Layout.twoOne.paneCount == 2)
    #expect(Layout.thirds.paneCount == 3)
}

@Test func fullFramesFillBounds() {
    let bounds = CGRect(x: 100, y: 50, width: 1200, height: 800)
    let frames = Layout.full.paneFrames(in: bounds)
    #expect(frames.count == 1)
    #expect(frames[0] == bounds)
}

@Test func halfFramesSplitEvenly() {
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let frames = Layout.half.paneFrames(in: bounds)
    #expect(frames.count == 2)
    #expect(frames[0] == CGRect(x: 0, y: 0, width: 600, height: 800))
    #expect(frames[1] == CGRect(x: 600, y: 0, width: 600, height: 800))
}

@Test func oneTwoFramesUseOneThirdTwoThirds() {
    let bounds = CGRect(x: 100, y: 50, width: 900, height: 400)
    let frames = Layout.oneTwo.paneFrames(in: bounds)
    #expect(frames.count == 2)
    #expect(abs(frames[0].width - 300) < 0.0001)
    #expect(abs(frames[1].width - 600) < 0.0001)
    #expect(frames[0].minX == 100)
    #expect(abs(frames[1].minX - 400) < 0.0001)
    #expect(frames[0].height == 400)
    #expect(frames[1].maxX == bounds.maxX)
}

@Test func twoOneFramesUseTwoThirdsOneThird() {
    let bounds = CGRect(x: 0, y: 0, width: 900, height: 100)
    let frames = Layout.twoOne.paneFrames(in: bounds)
    #expect(abs(frames[0].width - 600) < 0.0001)
    #expect(abs(frames[1].width - 300) < 0.0001)
}

@Test func thirdsFramesSplitEvenly() {
    let bounds = CGRect(x: 0, y: 0, width: 900, height: 200)
    let frames = Layout.thirds.paneFrames(in: bounds)
    #expect(frames.count == 3)
    #expect(frames[0].width == 300)
    #expect(frames[1].origin.x == 300)
    #expect(frames[2].origin.x == 600)
    #expect(frames[2].maxX == 900)
}

@Test func adjacentPaneHorizontal() {
    #expect(Layout.full.adjacentPane(from: 0, direction: .left) == nil)
    #expect(Layout.full.adjacentPane(from: 0, direction: .right) == nil)
    #expect(Layout.half.adjacentPane(from: 0, direction: .right) == 1)
    #expect(Layout.half.adjacentPane(from: 1, direction: .left) == 0)
    #expect(Layout.half.adjacentPane(from: 0, direction: .left) == nil)
    #expect(Layout.half.adjacentPane(from: 1, direction: .right) == nil)
    #expect(Layout.thirds.adjacentPane(from: 1, direction: .right) == 2)
    #expect(Layout.thirds.adjacentPane(from: 1, direction: .left) == 0)
}

@Test func adjacentPaneVerticalIsNil() {
    #expect(Layout.full.adjacentPane(from: 0, direction: .up) == nil)
    #expect(Layout.half.adjacentPane(from: 0, direction: .up) == nil)
    #expect(Layout.half.adjacentPane(from: 1, direction: .down) == nil)
    #expect(Layout.thirds.adjacentPane(from: 1, direction: .up) == nil)
}

@Test func paneIndexContainingPoint() {
    let bounds = CGRect(x: 0, y: 0, width: 900, height: 100)
    #expect(Layout.thirds.paneIndex(containing: CGPoint(x: 10, y: 10), in: bounds) == 0)
    #expect(Layout.thirds.paneIndex(containing: CGPoint(x: 450, y: 10), in: bounds) == 1)
    #expect(Layout.thirds.paneIndex(containing: CGPoint(x: 800, y: 10), in: bounds) == 2)
}

@Test func paneIndexFallsBackToNearest() {
    let bounds = CGRect(x: 0, y: 0, width: 900, height: 100)
    #expect(Layout.thirds.paneIndex(containing: CGPoint(x: -50, y: 10), in: bounds) == 0)
    #expect(Layout.thirds.paneIndex(containing: CGPoint(x: 2000, y: 10), in: bounds) == 2)
}

@Test func clampedPane() {
    #expect(Layout.full.clampedPane(-1) == 0)
    #expect(Layout.full.clampedPane(0) == 0)
    #expect(Layout.full.clampedPane(1) == 0)
    #expect(Layout.half.clampedPane(-1) == 0)
    #expect(Layout.half.clampedPane(0) == 0)
    #expect(Layout.half.clampedPane(1) == 1)
    #expect(Layout.half.clampedPane(2) == 1)
    #expect(Layout.thirds.clampedPane(2) == 2)
    #expect(Layout.thirds.clampedPane(5) == 2)
}

@Test func cycleLayout() {
    #expect(Layout.full.next() == .half)
    #expect(Layout.half.next() == .oneTwo)
    #expect(Layout.oneTwo.next() == .twoOne)
    #expect(Layout.twoOne.next() == .thirds)
    #expect(Layout.thirds.next() == .full)
}
