import CoreGraphics
import Foundation

public struct WindowID: Hashable, Sendable, Codable {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public struct SpaceID: Hashable, Sendable, Codable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public var persistenceKey: String {
        String(rawValue)
    }
}

/// Per-space tiling state: layout, pane assignment, switcher order, last focused assigned window, and per-pane focus.
public struct WorkspaceState: Equatable, Sendable {
    public var layout: Layout
    /// Assigned window → pane index. Unassigned windows are omitted.
    public var marks: [WindowID: Int]
    /// Switcher order for assigned windows. New assignments are appended.
    public var order: [WindowID]
    public var lastFocusedMarkedWindow: WindowID?
    /// Last focused window per pane. Used when returning to a pane via focus-direction.
    public var lastFocusedByPane: [Int: WindowID]
    public var defaultPane: Int

    public init(
        layout: Layout = .half,
        marks: [WindowID: Int] = [:],
        order: [WindowID] = [],
        lastFocusedMarkedWindow: WindowID? = nil,
        lastFocusedByPane: [Int: WindowID] = [:],
        defaultPane: Int = 0
    ) {
        self.layout = layout
        self.marks = marks
        self.order = order
        self.lastFocusedMarkedWindow = lastFocusedMarkedWindow
        self.lastFocusedByPane = lastFocusedByPane
        self.defaultPane = defaultPane
    }

    public func pane(for window: WindowID) -> Int? {
        marks[window]
    }

    public var markedWindows: [WindowID] {
        order
    }

    public func windows(in pane: Int) -> [WindowID] {
        order.filter { marks[$0] == pane }
    }

    /// Assigned windows that share `pane`, in switcher order (a subset of `order`).
    public func switcherCandidates(in pane: Int) -> [WindowID] {
        windows(in: pane)
    }

    /// Switcher rows for `pane`: assigned windows in order that are also in
    /// `present`, then `unassigned` windows that are not assigned to any pane
    /// and are in `present`. Windows already belonging to another pane are
    /// omitted even if they appear in `unassigned`.
    public func candidates(
        forPane pane: Int,
        unassigned: [WindowID],
        present: Set<WindowID>
    ) -> [WindowID] {
        let assigned = windows(in: pane).filter { present.contains($0) }
        var seen = Set(assigned)
        var result = assigned
        for id in unassigned where marks[id] == nil && present.contains(id) {
            if seen.insert(id).inserted {
                result.append(id)
            }
        }
        return result
    }

    /// Pane whose stacked windows the switcher should list.
    /// Assigned focused window → its pane; unassigned → pane under `focusedCenter`; else `defaultPane`.
    public func switcherPane(
        focusedWindow: WindowID?,
        focusedCenter: CGPoint?,
        bounds: CGRect
    ) -> Int {
        if let focusedWindow, let pane = pane(for: focusedWindow) {
            return pane
        }
        if let focusedCenter {
            return layout.paneIndex(containing: focusedCenter, in: bounds)
        }
        return layout.clampedPane(defaultPane)
    }

    /// Leading window of a pane in switcher order. Fallback when no remembered focus remains.
    public func leadingWindow(in pane: Int) -> WindowID? {
        windows(in: pane).first
    }

    /// Window to raise when focusing `pane`: remembered last focus if still assigned there, else the leading window.
    public func focusTarget(in pane: Int) -> WindowID? {
        if let remembered = lastFocusedByPane[pane], marks[remembered] == pane {
            return remembered
        }
        return leadingWindow(in: pane)
    }

    public mutating func mark(_ window: WindowID, pane: Int) {
        let pane = layout.clampedPane(pane)
        if marks[window] == nil {
            order.append(window)
        }
        marks[window] = pane
    }

    public mutating func unmark(_ window: WindowID) {
        marks.removeValue(forKey: window)
        order.removeAll { $0 == window }
        if lastFocusedMarkedWindow == window {
            lastFocusedMarkedWindow = nil
        }
        pruneStaleLastFocused()
    }

    /// Marks the window if unmarked, unmarks it if already marked.
    /// Returns whether the window is marked after the call.
    @discardableResult
    public mutating func toggleMark(_ window: WindowID, pane: Int) -> Bool {
        if marks[window] != nil {
            unmark(window)
            return false
        }
        mark(window, pane: pane)
        return true
    }

    public mutating func moveToPane(_ window: WindowID, pane: Int) {
        if marks[window] == nil {
            mark(window, pane: pane)
            return
        }
        marks[window] = layout.clampedPane(pane)
    }

    /// Assigns unseen windows to the pane under each window's center.
    public mutating func adoptUnseenWindows(
        _ windows: [(id: WindowID, center: CGPoint)],
        bounds: CGRect
    ) {
        for window in windows {
            if marks[window.id] == nil {
                mark(window.id, pane: layout.paneIndex(containing: window.center, in: bounds))
            }
        }
    }

    /// Moves a window one pane in `direction`. Unassigned windows are first assigned
    /// onto the default pane, then moved. Returns false if there is no adjacent pane.
    @discardableResult
    public mutating func moveInDirection(_ window: WindowID, direction: Direction) -> Bool {
        let current = marks[window] ?? layout.clampedPane(defaultPane)
        if marks[window] == nil {
            mark(window, pane: current)
        }
        guard let next = layout.adjacentPane(from: current, direction: direction) else {
            return false
        }
        marks[window] = next
        lastFocusedByPane[next] = window
        pruneStaleLastFocused()
        return true
    }

    public mutating func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        order = movingReorder(order, fromOffsets: source, toOffset: destination)
    }

    /// Reorders switcher candidates inside `pane` among themselves.
    /// Slots belonging to other panes keep their global positions.
    public mutating func reorderSwitcherCandidates(
        in pane: Int,
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        let candidates = switcherCandidates(in: pane)
        let reordered = movingReorder(candidates, fromOffsets: source, toOffset: destination)
        var iterator = reordered.makeIterator()
        order = order.map { id in
            if marks[id] == pane, let next = iterator.next() {
                return next
            }
            return id
        }
    }

    public mutating func reorder(from fromIndex: Int, to toIndex: Int) {
        guard order.indices.contains(fromIndex) else { return }
        let item = order.remove(at: fromIndex)
        let clamped = min(max(toIndex, 0), order.count)
        order.insert(item, at: clamped)
    }

    /// Pane that a newly created window should be assigned onto.
    public func paneForNewWindow() -> Int {
        if let last = lastFocusedMarkedWindow, let pane = marks[last] {
            return layout.clampedPane(pane)
        }
        return layout.clampedPane(defaultPane)
    }

    public mutating func recordFocus(_ window: WindowID) {
        if let pane = marks[window] {
            lastFocusedMarkedWindow = window
            lastFocusedByPane[pane] = window
        } else {
            lastFocusedMarkedWindow = nil
        }
    }

    public mutating func setLayout(_ layout: Layout) {
        self.layout = layout
        for window in order {
            if let pane = marks[window] {
                marks[window] = layout.clampedPane(pane)
            }
        }
    }

    public mutating func removeWindow(_ window: WindowID) {
        unmark(window)
    }

    private mutating func pruneStaleLastFocused() {
        lastFocusedByPane = lastFocusedByPane.filter { pane, id in
            marks[id] == pane
        }
    }
}

private func movingReorder<T>(
    _ items: [T],
    fromOffsets source: IndexSet,
    toOffset destination: Int
) -> [T] {
    var items = items
    let moving = source.sorted().compactMap { items.indices.contains($0) ? items[$0] : nil }
    for index in source.sorted().reversed() where items.indices.contains(index) {
        items.remove(at: index)
    }
    var dest = destination
    for index in source.sorted() where index < destination {
        dest -= 1
    }
    dest = min(max(dest, 0), items.count)
    items.insert(contentsOf: moving, at: dest)
    return items
}

/// In-memory store of per-space workspace state.
public struct WorkspaceStore: Equatable, Sendable {
    public var spaces: [SpaceID: WorkspaceState]
    public var defaultLayout: Layout
    public var defaultPane: Int

    public init(
        spaces: [SpaceID: WorkspaceState] = [:],
        defaultLayout: Layout = .half,
        defaultPane: Int = 0
    ) {
        self.spaces = spaces
        self.defaultLayout = defaultLayout
        self.defaultPane = defaultPane
    }

    public mutating func state(for space: SpaceID) -> WorkspaceState {
        if let existing = spaces[space] {
            return existing
        }
        let created = WorkspaceState(
            layout: defaultLayout,
            defaultPane: defaultPane
        )
        spaces[space] = created
        return created
    }

    public mutating func update(_ space: SpaceID, _ body: (inout WorkspaceState) -> Void) {
        var current = state(for: space)
        body(&current)
        spaces[space] = current
    }

    public func persistedState() -> PersistedState {
        var layouts: [String: Layout] = [:]
        for (space, state) in spaces {
            layouts[space.persistenceKey] = state.layout
        }
        return PersistedState(layouts: layouts)
    }

    public mutating func applyPersistedState(_ persisted: PersistedState) {
        for (key, layout) in persisted.layouts {
            guard let raw = UInt64(key) else { continue }
            let space = SpaceID(raw)
            update(space) { $0.setLayout(layout) }
        }
    }
}
