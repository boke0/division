import AppKit
import ApplicationServices
import DivisionKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private var statusItem: NSStatusItem?
    private let windowManager = WindowManager()
    private let spaceTracker = SpaceTracker()
    private var engine: TilingEngine?
    private var switcher: SwitcherPanelController?
    private var windowObserver: WindowObserver?
    private var layoutMenuItems: [NSMenuItem] = []
    private var accessibilityMenuItem: NSMenuItem?
    private var accessibilityPoll: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let engine = TilingEngine(windowManager: windowManager, spaceTracker: spaceTracker)
        self.engine = engine
        switcher = SwitcherPanelController(engine: engine)
        engine.onStateChanged = { [weak self] in
            self?.refreshLayoutMenu()
            self?.switcher?.reloadIfVisible()
        }

        // Register this process with TCC before any AX read (status item layout
        // queries focusedWindow and would otherwise look like a missing window).
        promptAccessibilityIfNeeded(openSettings: false)

        setupStatusItem()
        HotkeyCenter.shared.onPressed = { [weak self] id in
            self?.handleHotkey(id: id)
        }
        spaceTracker.onSpaceChanged = { [weak self] in
            self?.switcher?.hide()
            self?.engine?.handleSpaceChanged()
        }
        registerHotkeys()
        retryHotkeysUntilTrusted()
        startWindowObserver(engine: engine)
        engine.handleSpaceChanged()
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityPoll?.invalidate()
        accessibilityPoll = nil
        windowObserver?.stop()
        HotkeyCenter.shared.unregisterAll()
    }

    func applicationDidResignActive(_ notification: Notification) {
        if switcher?.isKey == true { return }
        switcher?.hide()
    }

    private func startWindowObserver(engine: TilingEngine) {
        windowObserver?.stop()
        windowObserver = nil
        let observer = WindowObserver()
        observer.onWindowCreated = { [weak engine] id in
            engine?.noteWindowCreated(id)
        }
        observer.onFocusChanged = { [weak engine] in
            engine?.noteFocusChanged()
        }
        observer.onWindowsChanged = { [weak engine] in
            engine?.pruneMissingWindows()
        }
        observer.start()
        windowObserver = observer
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.split.3x1",
                accessibilityDescription: "Division"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let axItem = NSMenuItem(
            title: "Enable Accessibility…",
            action: #selector(requestAccessibility),
            keyEquivalent: ""
        )
        accessibilityMenuItem = axItem
        menu.addItem(axItem)
        menu.addItem(.separator())

        let layoutHeader = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        layoutHeader.isEnabled = false
        menu.addItem(layoutHeader)

        layoutMenuItems = Layout.allCases.map { layout in
            let item = NSMenuItem(
                title: layout.displayName,
                action: #selector(selectLayout(_:)),
                keyEquivalent: ""
            )
            item.representedObject = layout.rawValue
            return item
        }
        for item in layoutMenuItems {
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfigFromMenu), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Division", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        refreshLayoutMenu()
    }

    private func registerHotkeys() {
        guard let config = engine?.config else { return }
        DivisionLog.event("division: AXIsProcessTrusted=\(AXIsProcessTrusted())")
        do {
            let bindings = try BindingResolver.resolve(config)
            HotkeyCenter.shared.register(bindings)
        } catch {
            DivisionLog.event("division: failed to resolve hotkeys: \(error)")
        }
    }

    private func handleHotkey(id: UInt32) {
        guard let action = HotkeyAction(rawValue: id) else { return }
        DivisionLog.event("division: hotkey \(action) isFocus=\(action.isFocus) isMove=\(action.isMove)")
        switch action {
        case .switcher:
            switcher?.toggle()
        default:
            if switcher?.isKey == true {
                DivisionLog.event("division: hotkey \(action) while switcher is key; still dispatching")
            }
            engine?.handleAction(action)
        }
    }

    private func refreshLayoutMenu() {
        refreshAccessibilityMenu()
        let current = engine?.currentLayout()
        for item in layoutMenuItems {
            item.state = (item.representedObject as? String) == current?.rawValue ? .on : .off
        }
    }

    private func refreshAccessibilityMenu() {
        let trusted = AXIsProcessTrusted()
        accessibilityMenuItem?.isHidden = trusted
        accessibilityMenuItem?.title = "Enable Accessibility…"
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let layout = Layout(rawValue: raw)
        else { return }
        engine?.setLayout(layout)
    }

    @objc private func reloadConfigFromMenu() {
        engine?.reloadConfig()
        registerHotkeys()
        refreshLayoutMenu()
        NSLog("division: config reloaded")
    }

    @objc private func requestAccessibility() {
        promptAccessibilityIfNeeded(openSettings: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func retryHotkeysUntilTrusted() {
        accessibilityPoll?.invalidate()
        guard !AXIsProcessTrusted() else { return }
        accessibilityPoll = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshAccessibilityMenu()
                guard AXIsProcessTrusted() else { return }
                self.accessibilityPoll?.invalidate()
                self.accessibilityPoll = nil
                self.registerHotkeys()
                if let engine = self.engine {
                    self.startWindowObserver(engine: engine)
                    engine.handleSpaceChanged()
                }
                DivisionLog.event("division: accessibility granted, observers restarted")
            }
        }
    }

    private func promptAccessibilityIfNeeded(openSettings: Bool) {
        UserDefaults.standard.removeObject(forKey: "division.didPromptAccessibility")
        DivisionLog.event("division: AX identity \(AccessibilityTrust.identityDescription())")
        let trusted = AXIsProcessTrusted()
        DivisionLog.event("division: AXIsProcessTrusted=\(trusted)")
        if trusted {
            refreshAccessibilityMenu()
            return
        }

        // Ask TCC to attach *this* process. Do not open Settings on launch:
        // that races the system prompt and leaves an older Division row looking "ON".
        let afterPrompt = AccessibilityTrust.requestIfUntrusted(reason: "prompt", force: true)
        DivisionLog.event("division: AX prompt requested, trusted after prompt=\(afterPrompt)")
        if openSettings {
            openAccessibilitySettings()
        }
        refreshAccessibilityMenu()
    }

    private func openAccessibilitySettings() {
        // Same URLs as Summon; Privacy_Accessibility is the TCC client list.
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for string in settingsURLs {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                DivisionLog.event("division: opened Privacy & Security (\(string))")
                return
            }
        }
        DivisionLog.event("division: failed to open Privacy & Security settings")
    }
}
