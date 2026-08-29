import AppKit
import CoreGraphics
import DivisionKit
import Foundation

@MainActor
final class TilingEngine {
    private(set) var config: AppConfig
    private var store: WorkspaceStore
    let windowManager: WindowManager
    let spaceTracker: SpaceTracker
    var onStateChanged: (() -> Void)?

    init(windowManager: WindowManager, spaceTracker: SpaceTracker) {
        self.windowManager = windowManager
        self.spaceTracker = spaceTracker
        let config = ConfigLoader.load()
        self.config = config
        var store = WorkspaceStore(
            defaultLayout: config.defaultLayout,
            defaultPane: config.defaultPane
        )
        store.applyPersistedState(ConfigLoader.loadState())
        self.store = store
    }

    func reloadConfig() {
        config = ConfigLoader.load()
        store.defaultLayout = config.defaultLayout
        store.defaultPane = config.defaultPane
    }

    func currentSpaceID() -> SpaceID? {
        spaceTracker.currentSpaceID(for: spaceScreen())
    }

    /// Falls back so layout/switcher hotkeys still have a workspace when CGS lookup fails.
    func resolvedSpaceID() -> SpaceID {
        currentSpaceID() ?? SpaceID(0)
    }

    func currentLayout() -> Layout {
        store.state(for: resolvedSpaceID()).layout
    }

    func markedWindows() -> [ManagedWindow] {
        let space = resolvedSpaceID()
        pruneGone(space)
        let state = store.state(for: space)
        return state.order.compactMap { windowManager.window(id: $0) }
    }

    func switcherWindows(in pane: Int) -> [ManagedWindow] {
        let space = resolvedSpaceID()
        pruneGone(space)
        let live = currentSpaceWindows()
        let state = store.state(for: space)
        let present = Set(live.map(\.id))
        let unassigned = live
            .filter { state.pane(for: $0.id) == nil }
            .sorted(by: Self.unassignedSort)
        let ids = state.candidates(
            forPane: pane,
            unassigned: unassigned.map(\.id),
            present: present
        )
        let byID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    func paneIndex(for windowID: WindowID) -> Int? {
        store.state(for: resolvedSpaceID()).pane(for: windowID)
    }

    func switcherPane() -> Int {
        let space = resolvedSpaceID()
        pruneGone(space)
        let state = store.state(for: space)
        return resolvedPane(in: state, focused: windowManager.focusedWindow())
    }

    /// Cocoa-coordinate frame of the pane in the current layout, using the same
    /// bounds resolution as `switcherPane()`.
    func paneFrame(_ pane: Int) -> CGRect {
        let layout = currentLayout()
        let bounds = tilingBounds(for: windowManager.focusedWindow()?.frame)
        return layout.paneFrames(in: bounds)[layout.clampedPane(pane)]
    }

    func handleAction(_ action: HotkeyAction) {
        switch action {
        case .cycleLayout:
            cycleLayout()
        case .focusLeft, .focusDown, .focusUp, .focusRight:
            if let direction = action.direction {
                focus(direction: direction)
            }
        case .moveLeft, .moveDown, .moveUp, .moveRight:
            if let direction = action.direction {
                moveFocused(direction: direction)
            }
        case .switcher:
            break
        }
    }

    func moveFocused(direction: Direction) {
        let resolution = windowManager.resolveFocusedWindow()
        DivisionLog.event(
            "move focus source workspaceFrontmost=\(resolution.workspaceFrontmost) axSystemApp=\(resolution.axSystemApp) snapshotAX=\(resolution.snapshotAX)"
        )
        guard let focused = resolution.window else {
            DivisionLog.event(
                "move skipped: no focused window (AX trusted=\(windowManager.isTrusted) \(windowManager.focusFailureDetail()))"
            )
            return
        }
        guard let space = currentSpaceID() else {
            DivisionLog.event("move skipped: no space id window=\(focused.id.rawValue)")
            return
        }
        pruneGone(space)
        let bounds = tilingBounds(for: focused.frame)
        var fromPane = -1
        var toPane = -1
        var moved = false
        store.update(space) { state in
            if state.pane(for: focused.id) == nil {
                state.mark(
                    focused.id,
                    pane: state.layout.paneIndex(
                        containing: CGPoint(x: focused.frame.midX, y: focused.frame.midY),
                        in: bounds
                    )
                )
            }
            fromPane = state.pane(for: focused.id) ?? state.layout.clampedPane(state.defaultPane)
            moved = state.moveInDirection(focused.id, direction: direction)
            toPane = state.pane(for: focused.id) ?? fromPane
            state.recordFocus(focused.id)
        }
        if moved {
            DivisionLog.event(
                "move window=\(focused.id.rawValue) from=\(fromPane) to=\(toPane) direction=\(direction)"
            )
            persist()
            retile(space)
            notify()
            return
        }
        if moveAcrossDisplay(focused, from: space, fromPane: fromPane, direction: direction) {
            persist()
            notify()
            return
        }
        DivisionLog.event(
            "move skipped: no adjacent pane window=\(focused.id.rawValue) from=\(fromPane) direction=\(direction)"
        )
        persist()
        retile(space)
        notify()
    }

    func focus(direction: Direction) {
        guard let space = currentSpaceID() else {
            DivisionLog.event("focus skipped: no space id direction=\(direction)")
            return
        }
        pruneGone(space)
        let resolution = windowManager.resolveFocusedWindow()
        let focused = resolution.window
        let sourceState = store.state(for: space)
        let currentPane = resolvedPane(in: sourceState, focused: focused)
        let occupancy = Self.occupancyDescription(sourceState)
        let neighbor = neighboringDestination(from: spaceScreen(), direction: direction)
        DivisionLog.event(
            "focus begin direction=\(direction) from=\(currentPane) occupancy=\(occupancy) focused=\(focused.map { "\($0.id.rawValue) \($0.appName)" } ?? "nil") workspaceFrontmost=\(resolution.workspaceFrontmost) axSystemApp=\(resolution.axSystemApp) snapshotAX=\(resolution.snapshotAX)"
        )
        switch resolveNavigationTarget(
            fromPane: currentPane,
            layout: sourceState.layout,
            direction: direction,
            neighborLayout: neighbor?.layout
        ) {
        case .pane(let nextPane):
            raiseFocusTarget(
                in: space,
                pane: nextPane,
                preferringSpaceFallback: false,
                direction: direction,
                occupancy: occupancy,
                focused: focused
            )
        case .neighbor(let destPane):
            guard let neighbor else { break }
            raiseFocusTarget(
                in: neighbor.space,
                pane: destPane,
                preferringSpaceFallback: true,
                direction: direction,
                occupancy: occupancy,
                focused: focused
            )
        case nil:
            DivisionLog.event(
                "focus skipped: no adjacent pane from=\(currentPane) direction=\(direction) layout=\(sourceState.layout) occupancy=\(occupancy) focused=\(focused.map { "\($0.id.rawValue) \($0.appName)" } ?? "nil")"
            )
        }
        notify()
    }

    func cycleLayout() {
        let from = currentLayout()
        let to = from.next()
        DivisionLog.event("cycleLayout \(from.rawValue) -> \(to.rawValue)")
        setLayout(to)
    }

    func setLayout(_ layout: Layout) {
        let space = resolvedSpaceID()
        DivisionLog.event("setLayout space=\(space.rawValue) layout=\(layout.rawValue)")
        store.update(space) { $0.setLayout(layout) }
        persist()
        retile(space)
        notify()
    }

    func handleSpaceChanged() {
        guard let space = currentSpaceID() else {
            notify()
            return
        }
        pruneGone(space)
        adoptUnseenOnScreen(space)
        retile(space)
        notify()
    }

    func raiseSwitcherCandidate(in pane: Int, at index: Int) {
        let space = resolvedSpaceID()
        let windows = switcherWindows(in: pane)
        guard windows.indices.contains(index) else { return }
        let id = windows[index].id
        store.update(space) { state in
            if state.pane(for: id) == nil {
                state.mark(id, pane: pane)
            }
            state.recordFocus(id)
        }
        DivisionLog.event(
            "switcher assign window=\(id.rawValue) pane=\(pane) space=\(space.rawValue)"
        )
        windowManager.raise(id)
        persist()
        retile(space)
        notify()
    }

    func reorderSwitcherCandidates(in pane: Int, fromOffsets source: IndexSet, toOffset destination: Int) {
        let space = resolvedSpaceID()
        store.update(space) { $0.reorderSwitcherCandidates(in: pane, fromOffsets: source, toOffset: destination) }
        notify()
    }

    func noteFocusChanged() {
        guard let space = currentSpaceID(), let focused = windowManager.focusedWindow() else { return }
        store.update(space) { $0.recordFocus(focused.id) }
    }

    func noteWindowCreated(_ id: WindowID) {
        guard windowManager.window(id: id) != nil else { return }
        if windowManager.isFloatingWindow(id) {
            DivisionLog.event("window created skipped: floating id=\(id.rawValue)")
            return
        }
        guard let space = currentSpaceID() else { return }
        pruneGone(space)
        store.update(space) { state in
            if state.pane(for: id) == nil {
                state.mark(id, pane: state.paneForNewWindow())
            }
            state.recordFocus(id)
        }
        retile(space)
        notify()
    }

    func noteWindowDestroyed(_ id: WindowID) {
        for space in Array(store.spaces.keys) {
            store.update(space) { $0.removeWindow(id) }
        }
        persist()
        notify()
    }

    func pruneMissingWindows() {
        for space in Array(store.spaces.keys) {
            pruneGone(space)
        }
        persist()
        notify()
    }

    func retileCurrent() {
        guard let space = currentSpaceID() else { return }
        retile(space)
    }

    private func retile(_ space: SpaceID, on screen: NSScreen? = nil) {
        pruneGone(space)
        let targetScreen = screen ?? spaceScreen()
        let live = windowsOnScreen(targetScreen)
        let liveIDs = Set(live.map(\.id))
        let bounds = windowManager.visibleFrame(for: targetScreen)
        let state = store.state(for: space)
        let frames = state.layout.paneFrames(in: bounds)
        DivisionLog.event(
            "retile space=\(space.rawValue) assigned=\(state.order.count) live=\(live.count) bounds=\(bounds)"
        )
        for windowID in state.order {
            guard liveIDs.contains(windowID) else {
                DivisionLog.event("retile skipped window=\(windowID.rawValue) not on current space")
                continue
            }
            guard let pane = state.pane(for: windowID), frames.indices.contains(pane) else {
                DivisionLog.event("retile skipped window=\(windowID.rawValue) missing pane")
                continue
            }
            if !windowManager.setFrame(windowID, frames[pane]) {
                DivisionLog.event("setFrame failed window=\(windowID.rawValue) pane=\(pane) frame=\(frames[pane])")
            }
        }
    }

    private func raiseFocusTarget(
        in space: SpaceID,
        pane: Int,
        preferringSpaceFallback: Bool,
        direction: Direction,
        occupancy: String,
        focused: ManagedWindow?
    ) {
        pruneGone(space)
        var target: WindowID?
        store.update(space) { state in
            target = preferringSpaceFallback
                ? state.focusTargetPreferringPane(pane)
                : state.focusTarget(in: pane)
            if let target {
                state.recordFocus(target)
            }
        }
        guard let target else {
            DivisionLog.event(
                "focus skipped: no window in target pane=\(pane) space=\(space.rawValue) assigned fallback=\(preferringSpaceFallback) occupancy=\(occupancy) focused=\(focused.map { "\($0.id.rawValue) \($0.appName)" } ?? "nil")"
            )
            return
        }
        if windowManager.raise(target) {
            DivisionLog.event(
                "focus raised window=\(target.rawValue) direction=\(direction) pane=\(pane) space=\(space.rawValue)"
            )
        } else {
            DivisionLog.event(
                "focus raise failed window=\(target.rawValue) direction=\(direction) pane=\(pane) space=\(space.rawValue)"
            )
        }
    }

    @discardableResult
    private func moveAcrossDisplay(
        _ focused: ManagedWindow,
        from space: SpaceID,
        fromPane: Int,
        direction: Direction
    ) -> Bool {
        guard let dest = neighboringDestination(from: spaceScreen(), direction: direction) else {
            return false
        }
        let sourceLayout = store.state(for: space).layout
        let destPane = landingPane(
            direction: direction,
            sourceLayout: sourceLayout,
            sourcePane: fromPane,
            destinationLayout: dest.layout
        )
        store.transfer(focused.id, from: space, to: dest.space, pane: destPane)
        if space != dest.space {
            let moved = PrivateAPI.moveWindow(focused.id.rawValue, toSpace: dest.space.rawValue)
            DivisionLog.event(
                "move window to space issued=\(moved) window=\(focused.id.rawValue) fromSpace=\(space.rawValue) toSpace=\(dest.space.rawValue)"
            )
        }
        let destBounds = windowManager.visibleFrame(for: dest.screen)
        let destFrames = store.state(for: dest.space).layout.paneFrames(in: destBounds)
        if destFrames.indices.contains(destPane) {
            if !windowManager.setFrame(focused.id, destFrames[destPane]) {
                DivisionLog.event(
                    "move across display setFrame failed window=\(focused.id.rawValue) pane=\(destPane) frame=\(destFrames[destPane])"
                )
            }
        }
        retile(dest.space, on: dest.screen)
        if windowManager.raise(focused.id) {
            DivisionLog.event(
                "move window=\(focused.id.rawValue) across display from=\(fromPane) to=\(destPane) direction=\(direction) space=\(dest.space.rawValue)"
            )
        } else {
            DivisionLog.event(
                "move across display raise failed window=\(focused.id.rawValue) pane=\(destPane) space=\(dest.space.rawValue)"
            )
        }
        return true
    }

    private func neighboringDestination(
        from screen: NSScreen?,
        direction: Direction
    ) -> (screen: NSScreen, space: SpaceID, layout: Layout)? {
        guard let destScreen = neighboringScreen(from: screen, direction: direction) else {
            return nil
        }
        guard let destSpace = spaceTracker.currentSpaceID(for: destScreen) else {
            return nil
        }
        pruneGone(destSpace)
        return (destScreen, destSpace, store.state(for: destSpace).layout)
    }

    private func neighboringScreen(from screen: NSScreen?, direction: Direction) -> NSScreen? {
        guard let screen else { return nil }
        let screens = NSScreen.screens
        guard let index = adjacentFrameIndex(
            from: screen.frame,
            among: screens.map(\.frame),
            direction: direction
        ) else {
            return nil
        }
        return screens[index]
    }

    private func pruneGone(_ space: SpaceID) {
        let manageable = Set(windowManager.allWindows().map(\.id))
        store.update(space) { state in
            let gone = state.order.filter { !manageable.contains($0) }
            for id in gone {
                state.removeWindow(id)
            }
        }
    }

    private func adoptUnseenOnScreen(_ space: SpaceID) {
        let live = currentSpaceWindows()
        let bounds = tilingBounds(for: windowManager.focusedWindow()?.frame ?? live.first?.frame)
        let adoptable = live.filter { !windowManager.isFloatingWindow($0.id) }
        store.update(space) { state in
            state.adoptUnseenWindows(
                adoptable.map { (id: $0.id, center: CGPoint(x: $0.frame.midX, y: $0.frame.midY)) },
                bounds: bounds
            )
        }
    }

    private func currentSpaceWindows() -> [ManagedWindow] {
        windowsOnScreen(spaceScreen())
    }

    private func windowsOnScreen(_ screen: NSScreen?) -> [ManagedWindow] {
        let onScreen = onScreenWindowIDs()
        let screenFrame = screen?.frame
        return windowManager.allWindows().filter { window in
            guard onScreen.contains(window.id) else { return false }
            guard let screenFrame else { return true }
            return screenFrame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY))
        }
    }

    private static func unassignedSort(_ lhs: ManagedWindow, _ rhs: ManagedWindow) -> Bool {
        let app = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
        if app != .orderedSame {
            return app == .orderedAscending
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func persist() {
        do {
            try ConfigLoader.saveState(store.persistedState())
        } catch {
            NSLog("division: failed to save state: \(error)")
        }
    }

    private func notify() {
        onStateChanged?()
    }

    private func resolvedPane(in state: WorkspaceState, focused: ManagedWindow?) -> Int {
        state.switcherPane(
            focusedWindow: focused?.id,
            focusedCenter: focused.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) },
            bounds: tilingBounds(for: focused?.frame)
        )
    }

    private static func occupancyDescription(_ state: WorkspaceState) -> String {
        (0..<state.layout.paneCount).map { pane in
            "\(pane):\(state.windows(in: pane).count)"
        }.joined(separator: ",")
    }

    private func tilingBounds(for frame: CGRect?) -> CGRect {
        if let frame {
            return windowManager.visibleFrame(containing: frame)
        }
        return windowManager.visibleFrame(for: NSScreen.main)
    }

    private func spaceScreen() -> NSScreen? {
        if let focused = windowManager.focusedWindow() {
            return screenContaining(focused.frame)
        }
        return NSScreen.main
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
    }

    private func onScreenWindowIDs() -> Set<WindowID> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids: Set<WindowID> = []
        for entry in info {
            if let number = entry[kCGWindowNumber as String] as? NSNumber {
                ids.insert(WindowID(number.uint32Value))
            }
        }
        return ids
    }
}
