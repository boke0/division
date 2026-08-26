import AppKit
import DivisionKit
import SwiftUI

final class SwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SwitcherPanelController: NSObject {
    private let engine: TilingEngine
    private let model = SwitcherModel()
    private let panel: SwitcherPanel
    private var eventMonitor: Any?

    private var activePane = 0

    init(engine: TilingEngine) {
        self.engine = engine
        panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let hosting = NSHostingView(
            rootView: SwitcherView(model: model, onMove: { [weak self] source, destination in
                self?.handleMove(fromOffsets: source, toOffset: destination)
            })
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var isKey: Bool {
        panel.isKeyWindow
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        activePane = engine.switcherPane()
        model.reload(from: engine, pane: activePane)
        model.resetInput()
        centerOnActivePane()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        startEventMonitor()
    }

    func hide() {
        stopEventMonitor()
        panel.orderOut(nil)
    }

    func reloadIfVisible() {
        guard panel.isVisible else { return }
        model.reload(from: engine, pane: activePane)
    }

    private func handleMove(fromOffsets source: IndexSet, toOffset destination: Int) {
        let assignedCount = model.items.filter(\.isAssigned).count
        let inPane = IndexSet(source.filter { $0 < assignedCount })
        guard !inPane.isEmpty else { return }
        engine.reorderSwitcherCandidates(
            in: activePane,
            fromOffsets: inPane,
            toOffset: min(destination, assignedCount)
        )
        model.reload(from: engine, pane: activePane)
    }

    private func handleSelect(index: Int) {
        engine.raiseSwitcherCandidate(in: activePane, at: index)
        hide()
    }

    private func centerOnActivePane() {
        let pane = engine.paneFrame(activePane)
        let size = panel.frame.size
        var origin = NSPoint(
            x: pane.midX - size.width / 2,
            y: pane.midY - size.height / 2
        )
        // Panes narrower than the panel would push it off screen; keep it visible.
        let visible = engine.windowManager.visibleFrame(containing: pane)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let command = SwitcherKeyBinding.resolve(event) else {
            return false
        }
        switch command {
        case .digit(let character):
            model.appendDigit(character)
        case .delete:
            model.deleteLastDigit()
        case .confirm:
            if let index = model.session.confirmIndex() {
                handleSelect(index: index)
            }
        case .hide:
            hide()
        case .moveUp:
            model.moveHighlight(by: -1)
        case .moveDown:
            model.moveHighlight(by: 1)
        }
        return true
    }
}
