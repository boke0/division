import CoreGraphics
import Foundation
import Testing
@testable import DivisionKit

private let w1 = WindowID(1)
private let w2 = WindowID(2)
private let w3 = WindowID(3)
private let w4 = WindowID(4)

@Test func markAppendsInAdditionOrder() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 1)
    state.mark(w3, pane: 0)
    #expect(state.order == [w1, w2, w3])
    #expect(state.pane(for: w1) == 0)
    #expect(state.pane(for: w2) == 1)
    #expect(state.windows(in: 0) == [w1, w3])
}

@Test func remakingDoesNotDuplicateOrder() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w1, pane: 1)
    #expect(state.order == [w1])
    #expect(state.pane(for: w1) == 1)
}

@Test func toggleMarkAddsThenRemoves() {
    var state = WorkspaceState()
    #expect(state.toggleMark(w1, pane: 1) == true)
    #expect(state.pane(for: w1) == 1)
    #expect(state.toggleMark(w1, pane: 0) == false)
    #expect(state.pane(for: w1) == nil)
    #expect(state.order.isEmpty)
}

@Test func unmarkRemovesFromOrderAndFocus() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 1)
    state.recordFocus(w1)
    state.unmark(w1)
    #expect(state.order == [w2])
    #expect(state.lastFocusedMarkedWindow == nil)
}

@Test func moveInDirectionShiftsPane() {
    var state = WorkspaceState(layout: .thirds)
    state.mark(w1, pane: 0)
    let movedRight = state.moveInDirection(w1, direction: .right)
    #expect(movedRight)
    #expect(state.pane(for: w1) == 1)
    let movedAgain = state.moveInDirection(w1, direction: .right)
    #expect(movedAgain)
    #expect(state.pane(for: w1) == 2)
    let blocked = state.moveInDirection(w1, direction: .right)
    #expect(!blocked)
    #expect(state.pane(for: w1) == 2)
}

@Test func moveInDirectionMarksUnmarkedOntoDefaultThenMoves() {
    var state = WorkspaceState(layout: .half, defaultPane: 0)
    let moved = state.moveInDirection(w1, direction: .right)
    #expect(moved)
    #expect(state.pane(for: w1) == 1)
    #expect(state.order == [w1])
}

@Test func moveVerticalDoesNothing() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    let moved = state.moveInDirection(w1, direction: .up)
    #expect(!moved)
    #expect(state.pane(for: w1) == 0)
}

@Test func layoutChangeClampsPaneIndex() {
    var state = WorkspaceState(layout: .thirds)
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 1)
    state.mark(w3, pane: 2)
    state.setLayout(.half)
    #expect(state.layout == .half)
    #expect(state.pane(for: w1) == 0)
    #expect(state.pane(for: w2) == 1)
    #expect(state.pane(for: w3) == 1)
}

@Test func paneForNewWindowUsesLastFocusedMarkedPane() {
    var state = WorkspaceState(defaultPane: 0)
    state.mark(w1, pane: 1)
    state.recordFocus(w1)
    #expect(state.paneForNewWindow() == 1)
}

@Test func paneForNewWindowFallsBackToDefaultWhenFocusUnmarked() {
    var state = WorkspaceState(layout: .thirds, defaultPane: 2)
    state.mark(w1, pane: 0)
    state.recordFocus(w1)
    state.recordFocus(w2)
    #expect(state.lastFocusedMarkedWindow == nil)
    #expect(state.paneForNewWindow() == 2)
}

@Test func paneForNewWindowFallsBackWhenLastMarkedWasUnmarked() {
    var state = WorkspaceState(defaultPane: 0)
    state.mark(w1, pane: 1)
    state.recordFocus(w1)
    state.unmark(w1)
    #expect(state.paneForNewWindow() == 0)
}

@Test func reorderByIndex() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    state.mark(w3, pane: 0)
    state.reorder(from: 2, to: 0)
    #expect(state.order == [w3, w1, w2])
}

@Test func reorderFromOffsets() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    state.mark(w3, pane: 0)
    state.mark(w4, pane: 0)
    state.reorder(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    #expect(state.order == [w2, w3, w1, w4])
}

@Test func leadingWindowFollowsOrder() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 1)
    state.mark(w3, pane: 0)
    #expect(state.leadingWindow(in: 0) == w1)
    #expect(state.leadingWindow(in: 1) == w2)
}

@Test func focusTargetRemembersLastFocusedInPaneNotLeading() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    #expect(state.windows(in: 0) == [w1, w2])
    state.recordFocus(w2)
    #expect(state.focusTarget(in: 0) == w2)
    #expect(state.leadingWindow(in: 0) == w1)
}

@Test func focusTargetFallsBackToLeadingAfterUnassign() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    state.recordFocus(w2)
    state.unmark(w2)
    #expect(state.focusTarget(in: 0) == w1)
}

@Test func focusTargetFallsBackToLeadingAfterRemove() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    state.recordFocus(w2)
    state.removeWindow(w2)
    #expect(state.focusTarget(in: 0) == w1)
}

@Test func moveInDirectionTransfersLastFocusedToDestinationPane() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    state.mark(w3, pane: 1)
    state.recordFocus(w2)
    #expect(state.focusTarget(in: 0) == w2)
    let moved = state.moveInDirection(w2, direction: .right)
    #expect(moved)
    #expect(state.pane(for: w2) == 1)
    #expect(state.focusTarget(in: 1) == w2)
    #expect(state.focusTarget(in: 0) == w1)
    #expect(state.lastFocusedByPane[0] != w2)
}

@Test func switcherCandidatesAreWindowsInPaneInOrder() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 1)
    state.mark(w3, pane: 0)
    state.mark(w4, pane: 1)
    #expect(state.switcherCandidates(in: 0) == [w1, w3])
    #expect(state.switcherCandidates(in: 1) == [w2, w4])
    #expect(state.switcherCandidates(in: 2) == [])
}

@Test func candidatesIncludeUnassignedNotOtherPanes() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    state.mark(w3, pane: 1)
    let present: Set<WindowID> = [w1, w2, w3, w4]
    #expect(state.candidates(forPane: 0, unassigned: [w4], present: present) == [w1, w2, w4])
    #expect(state.candidates(forPane: 1, unassigned: [w4], present: present) == [w3, w4])
    #expect(!state.candidates(forPane: 0, unassigned: [w4], present: present).contains(w3))
    #expect(state.candidates(forPane: 0, unassigned: [w3, w4], present: present) == [w1, w2, w4])
}

@Test func confirmingUnassignedWindowAssignsToCurrentPane() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    state.mark(w3, pane: 1)
    let present: Set<WindowID> = [w1, w2, w3, w4]
    #expect(state.candidates(forPane: 0, unassigned: [w4], present: present) == [w1, w2, w4])

    state.mark(w4, pane: 0)

    #expect(state.pane(for: w4) == 0)
    #expect(state.windows(in: 0) == [w1, w2, w4])
    #expect(state.candidates(forPane: 0, unassigned: [], present: present).contains(w4))
    #expect(state.candidates(forPane: 0, unassigned: [], present: present) == [w1, w2, w4])
    #expect(state.candidates(forPane: 0, unassigned: [w4], present: present) == [w1, w2, w4])
    #expect(state.candidates(forPane: 1, unassigned: [w4], present: present) == [w3])
    #expect(!state.candidates(forPane: 1, unassigned: [w4], present: present).contains(w4))
}

@Test func adoptUnseenUsesPaneUnderCenter() {
    var state = WorkspaceState(layout: .half)
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
    state.adoptUnseenWindows(
        [(id: w1, center: CGPoint(x: 50, y: 50)), (id: w2, center: CGPoint(x: 150, y: 50))],
        bounds: bounds
    )
    #expect(state.pane(for: w1) == 0)
    #expect(state.pane(for: w2) == 1)
    state.adoptUnseenWindows(
        [(id: w1, center: CGPoint(x: 150, y: 50))],
        bounds: bounds
    )
    #expect(state.pane(for: w1) == 0)
}

@Test func emptyPaneCandidatesAreUnassignedOnly() {
    var state = WorkspaceState()
    state.mark(w3, pane: 1)
    let present: Set<WindowID> = [w3, w4]
    #expect(state.candidates(forPane: 0, unassigned: [w4], present: present) == [w4])
    #expect(state.candidates(forPane: 0, unassigned: [w3, w4], present: present) == [w4])
}

@Test func candidatesOmitAssignedWindowsNotPresent() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 0)
    let present: Set<WindowID> = [w1, w4]
    #expect(state.candidates(forPane: 0, unassigned: [w4], present: present) == [w1, w4])
    #expect(!state.candidates(forPane: 0, unassigned: [w4], present: present).contains(w2))
}

@Test func switcherPaneUsesMarkedWindowPane() {
    var state = WorkspaceState(layout: .half, defaultPane: 1)
    state.mark(w1, pane: 0)
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
    #expect(
        state.switcherPane(
            focusedWindow: w1,
            focusedCenter: CGPoint(x: 150, y: 50),
            bounds: bounds
        ) == 0
    )
}

@Test func switcherPaneUsesCenterWhenUnmarked() {
    let state = WorkspaceState(layout: .half, defaultPane: 0)
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)
    #expect(
        state.switcherPane(
            focusedWindow: w1,
            focusedCenter: CGPoint(x: 150, y: 50),
            bounds: bounds
        ) == 1
    )
}

@Test func switcherPaneFallsBackToDefaultWhenUnknown() {
    let state = WorkspaceState(layout: .thirds, defaultPane: 2)
    #expect(
        state.switcherPane(focusedWindow: nil, focusedCenter: nil, bounds: .zero) == 2
    )
}

@Test func reorderSwitcherCandidatesPreservesOtherPanes() {
    var state = WorkspaceState()
    state.mark(w1, pane: 0)
    state.mark(w2, pane: 1)
    state.mark(w3, pane: 0)
    state.mark(w4, pane: 1)
    state.reorderSwitcherCandidates(in: 0, fromOffsets: IndexSet(integer: 1), toOffset: 0)
    #expect(state.order == [w3, w2, w1, w4])
    #expect(state.switcherCandidates(in: 0) == [w3, w1])
    #expect(state.switcherCandidates(in: 1) == [w2, w4])
}

@Test func storeCreatesStateWithDefaultsAndPersistsLayouts() {
    var store = WorkspaceStore(defaultLayout: .oneTwo, defaultPane: 1)
    let space = SpaceID(99)
    #expect(store.state(for: space).layout == .oneTwo)
    store.update(space) { $0.setLayout(.thirds) }
    let persisted = store.persistedState()
    #expect(persisted.layouts["99"] == .thirds)

    var restored = WorkspaceStore(defaultLayout: .half)
    restored.applyPersistedState(persisted)
    #expect(restored.state(for: space).layout == .thirds)
}
