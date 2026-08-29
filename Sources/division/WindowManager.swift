import AppKit
import ApplicationServices
import DivisionKit
import Foundation

struct ManagedWindow: Equatable, Sendable {
    var id: WindowID
    var pid: pid_t
    var title: String
    var appName: String
    var bundleIdentifier: String?
    var frame: CGRect
}

struct FocusResolution {
    var window: ManagedWindow?
    var appName: String = "?"
    var bundle: String = "?"
    var role: String = "?"
    var subrole: String = "?"
    var axError: Int32 = 0
    var workspaceFrontmost: String = "?"
    var axSystemApp: String = "?"
    var snapshotAX: String = "?"

    var markLogLine: String {
        "mark focused app=\(appName) bundle=\(bundle) role=\(role) subrole=\(subrole) axError=\(axError)"
    }
}

@MainActor
final class WindowManager {
    private var ownPID: pid_t {
        ProcessInfo.processInfo.processIdentifier
    }

    private let excludedWindowSubroles: Set<String> = [
        kAXFloatingWindowSubrole as String,
        kAXSystemFloatingWindowSubrole as String,
        "AXPictureWindow",
        "AXOverlay",
        "AXPopover",
        "AXTooltip",
    ]

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func focusedWindow() -> ManagedWindow? {
        resolveFocusedWindow().window
    }

    func resolveFocusedWindow() -> FocusResolution {
        if !isTrusted {
            AccessibilityTrust.requestIfUntrusted(reason: "focusedWindow")
        }

        var resolution = FocusResolution()
        let workspaceApp = NSWorkspace.shared.frontmostApplication
        let (axApp, axAppError) = axSystemWideFocusedApplication()
        let snapshot = HotkeyCenter.shared.recentFocusSnapshot()
        resolution.workspaceFrontmost = describe(workspaceApp)
        resolution.axSystemApp = describe(axApp)
        resolution.snapshotAX = snapshot?.axName ?? "none"
        if axApp == nil {
            resolution.axError = axAppError.rawValue
        }

        var candidates: [NSRunningApplication] = []
        var seen = Set<pid_t>()
        func appendCandidate(_ app: NSRunningApplication?) {
            guard let app, app.processIdentifier != ownPID, !app.isTerminated else { return }
            if seen.insert(app.processIdentifier).inserted {
                candidates.append(app)
            }
        }
        if let snapshotPID = snapshot?.axPID {
            appendCandidate(NSRunningApplication(processIdentifier: snapshotPID))
        }
        appendCandidate(axApp)
        appendCandidate(workspaceApp)

        for app in candidates {
            let read = readFocusedWindow(of: app)
            resolution.appName = app.localizedName ?? "pid=\(app.processIdentifier)"
            resolution.bundle = app.bundleIdentifier ?? "nil"
            resolution.role = read.role
            resolution.subrole = read.subrole
            resolution.axError = read.axError.rawValue
            if let window = read.window {
                resolution.window = window
                return resolution
            }
        }

        if let fromElement = windowFromSystemWideFocusedElement() {
            resolution.appName = fromElement.window?.appName ?? resolution.appName
            resolution.bundle = fromElement.window?.bundleIdentifier ?? resolution.bundle
            resolution.role = fromElement.role
            resolution.subrole = fromElement.subrole
            resolution.axError = fromElement.axError.rawValue
            if let window = fromElement.window {
                resolution.window = window
                return resolution
            }
        }

        if let window = frontmostForeignWindowFromList() {
            resolution.window = window
            resolution.appName = window.appName
            resolution.bundle = window.bundleIdentifier ?? "nil"
            return resolution
        }

        return resolution
    }

    func focusFailureDetail() -> String {
        let trusted = isTrusted
        let resolution = resolveFocusedWindow()
        if let window = resolution.window {
            return "unexpected: resolved \(window.appName) id=\(window.id.rawValue) (AX trusted=\(trusted))"
        }
        return "workspaceFrontmost=\(resolution.workspaceFrontmost) axSystemApp=\(resolution.axSystemApp) app=\(resolution.appName) bundle=\(resolution.bundle) role=\(resolution.role) subrole=\(resolution.subrole) axError=\(resolution.axError) (AX trusted=\(trusted))"
    }

    func window(id: WindowID) -> ManagedWindow? {
        let layers = cgWindowLayers()
        for app in regularApplications() {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            for element in windows(of: appElement) {
                if windowIdentifier(for: element, pid: app.processIdentifier).map(WindowID.init) == id {
                    return makeWindow(element, app: app, layers: layers)
                }
            }
        }
        return nil
    }

    func allWindows() -> [ManagedWindow] {
        let layers = cgWindowLayers()
        var result: [ManagedWindow] = []
        for app in regularApplications() {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            for element in windows(of: appElement) {
                if let window = makeWindow(element, app: app, layers: layers) {
                    result.append(window)
                }
            }
        }
        return result
    }

    @discardableResult
    func setFrame(_ id: WindowID, _ cocoaFrame: CGRect) -> Bool {
        guard let (element, _) = axWindow(id) else {
            DivisionLog.event("setFrame failed: axWindow nil id=\(id.rawValue) AX trusted=\(isTrusted)")
            return false
        }
        let axOrigin = axOrigin(for: cocoaFrame)
        var point = axOrigin
        var size = cocoaFrame.size
        guard let positionValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            DivisionLog.event("setFrame failed: AXValueCreate id=\(id.rawValue)")
            return false
        }
        let pos1 = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        let sizeStatus = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let pos2 = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        if pos1 != .success || sizeStatus != .success || pos2 != .success {
            DivisionLog.event(
                "setFrame failed id=\(id.rawValue) pos=\(pos1.rawValue) size=\(sizeStatus.rawValue) pos2=\(pos2.rawValue) AX trusted=\(isTrusted)"
            )
            return false
        }
        return true
    }

    @discardableResult
    func raise(_ id: WindowID) -> Bool {
        guard let (element, pid) = axWindow(id) else {
            DivisionLog.event("raise failed: axWindow nil id=\(id.rawValue) AX trusted=\(isTrusted)")
            return false
        }
        let raiseStatus = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        let mainStatus = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if let app = NSRunningApplication(processIdentifier: pid) {
            NSApp.yieldActivation(to: app)
            app.activate()
        }
        if raiseStatus != .success {
            DivisionLog.event("raise failed id=\(id.rawValue) action=\(raiseStatus.rawValue) main=\(mainStatus.rawValue)")
            return false
        }
        return true
    }

    /// True when AX reports the window size is not settable (dialogs, palettes, fixed-size popups).
    func isFloatingWindow(_ id: WindowID) -> Bool {
        guard let (element, _) = axWindow(id) else { return false }
        var settable: DarwinBoolean = true
        let status = AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        if status != .success {
            return false
        }
        return !settable.boolValue
    }

    func visibleFrame(containing cocoaFrame: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(cocoaFrame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.visibleFrame ?? cocoaFrame
    }

    func visibleFrame(for screen: NSScreen?) -> CGRect {
        (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
    }

    private func describe(_ app: NSRunningApplication?) -> String {
        guard let app else { return "nil" }
        let name = app.localizedName ?? "pid=\(app.processIdentifier)"
        if app.processIdentifier == ownPID {
            return "\(name) (self)"
        }
        return name
    }

    private func axSystemWideFocusedApplication() -> (NSRunningApplication?, AXError) {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        if error == .apiDisabled {
            AccessibilityTrust.requestIfUntrusted(reason: "kAXErrorAPIDisabled")
            return (nil, error)
        }
        guard error == .success, let value else {
            return (nil, error)
        }
        let appElement = value as! AXUIElement
        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(appElement, &pid)
        guard pidError == .success else {
            return (nil, pidError)
        }
        return (NSRunningApplication(processIdentifier: pid), error)
    }

    private func readFocusedWindow(of app: NSRunningApplication) -> (
        window: ManagedWindow?,
        role: String,
        subrole: String,
        axError: AXError
    ) {
        guard app.processIdentifier != ownPID else {
            return (nil, "?", "?", .invalidUIElement)
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        if error == .apiDisabled {
            AccessibilityTrust.requestIfUntrusted(reason: "kAXErrorAPIDisabled")
            return (nil, "?", "?", error)
        }
        if error != .success || value == nil {
            var mainValue: CFTypeRef?
            let mainError = AXUIElementCopyAttributeValue(
                appElement,
                kAXMainWindowAttribute as CFString,
                &mainValue
            )
            if let mainValue {
                value = mainValue
                if error != .success {
                    error = mainError
                }
            }
        }
        guard let value else {
            return (nil, "?", "?", error)
        }
        let element = value as! AXUIElement
        let role = copyString(element, kAXRoleAttribute as CFString) ?? "?"
        let subrole = copyString(element, kAXSubroleAttribute as CFString) ?? "nil"
        if let window = makeWindow(element, app: app, layers: cgWindowLayers()) {
            return (window, role, subrole, error)
        }
        if looksLikeStandardWindow(role: role, subrole: subrole),
           windowIdentifier(for: element, pid: app.processIdentifier) == nil
        {
            DivisionLog.event(
                "_AXUIElementGetWindow failed app=\(app.localizedName ?? "?") bundle=\(app.bundleIdentifier ?? "nil") role=\(role) subrole=\(subrole) axError=\(error.rawValue)"
            )
        }
        return (nil, role, subrole, error)
    }

    private func windowFromSystemWideFocusedElement() -> (
        window: ManagedWindow?,
        role: String,
        subrole: String,
        axError: AXError
    )? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard error == .success, let value else { return nil }
        let focused = value as! AXUIElement
        var windowValue: CFTypeRef?
        let windowError = AXUIElementCopyAttributeValue(
            focused,
            kAXWindowAttribute as CFString,
            &windowValue
        )
        let element: AXUIElement
        if windowError == .success, let windowValue {
            element = windowValue as! AXUIElement
        } else {
            element = focused
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid != ownPID,
              let app = NSRunningApplication(processIdentifier: pid)
        else {
            return nil
        }
        let role = copyString(element, kAXRoleAttribute as CFString) ?? "?"
        let subrole = copyString(element, kAXSubroleAttribute as CFString) ?? "nil"
        return (makeWindow(element, app: app, layers: cgWindowLayers()), role, subrole, error)
    }

    private func frontmostForeignWindowFromList() -> ManagedWindow? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let skippedBundles: Set<String> = [
            "com.apple.dock",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.WindowManager",
            "com.apple.loginwindow",
        ]
        for entry in info {
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            guard let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(pidNumber.intValue)
            guard pid != ownPID else { continue }
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular,
                  !app.isTerminated
            else { continue }
            if let bundle = app.bundleIdentifier, skippedBundles.contains(bundle) {
                continue
            }
            if let bounds = entry[kCGWindowBounds as String] as? [String: Any] {
                let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
                let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
                if width < 50 || height < 50 { continue }
            }
            if let number = entry[kCGWindowNumber as String] as? NSNumber,
               let window = window(id: WindowID(number.uint32Value))
            {
                return window
            }
            if let window = readFocusedWindow(of: app).window {
                return window
            }
        }
        return nil
    }

    private func regularApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            !app.isTerminated
                && app.activationPolicy == .regular
                && app.processIdentifier != ownPID
        }
    }

    private func windows(of appElement: AXUIElement) -> [AXUIElement] {
        guard let value = copyValue(appElement, kAXWindowsAttribute as CFString) else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private func axWindow(_ id: WindowID) -> (AXUIElement, pid_t)? {
        for app in regularApplications() {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            for element in windows(of: appElement) {
                if windowIdentifier(for: element, pid: app.processIdentifier).map(WindowID.init) == id {
                    return (element, app.processIdentifier)
                }
            }
        }
        return nil
    }

    private func makeWindow(
        _ element: AXUIElement,
        app: NSRunningApplication,
        layers: [CGWindowID: Int]
    ) -> ManagedWindow? {
        let role = copyString(element, kAXRoleAttribute as CFString) ?? "?"
        let subrole = copyString(element, kAXSubroleAttribute as CFString)
        guard looksLikeStandardWindow(role: role, subrole: subrole) else { return nil }
        guard let cgID = windowIdentifier(for: element, pid: app.processIdentifier) else { return nil }
        let title = copyString(element, kAXTitleAttribute as CFString) ?? ""
        guard WindowEligibility.shouldTile(title: title, layer: layers[cgID]) else { return nil }
        let frame = cocoaFrame(of: element)
        return ManagedWindow(
            id: WindowID(cgID),
            pid: app.processIdentifier,
            title: title,
            appName: app.localizedName ?? "",
            bundleIdentifier: app.bundleIdentifier,
            frame: frame
        )
    }

    /// Window role, excluding palettes / floating chrome / tooltips. Empty and AXUnknown subroles are allowed.
    private func looksLikeStandardWindow(role: String, subrole: String?) -> Bool {
        guard role == (kAXWindowRole as String) else { return false }
        if let subrole, excludedWindowSubroles.contains(subrole) {
            return false
        }
        return true
    }

    private func cgWindowLayers() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var layers: [CGWindowID: Int] = [:]
        layers.reserveCapacity(info.count)
        for entry in info {
            guard let number = entry[kCGWindowNumber as String] as? NSNumber else { continue }
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            layers[CGWindowID(number.uint32Value)] = layer
        }
        return layers
    }

    private func windowIdentifier(for element: AXUIElement, pid: pid_t) -> CGWindowID? {
        if let identifier = PrivateAPI.windowID(for: element) {
            return identifier
        }
        return windowIDFromWindowList(pid: pid, element: element)
    }

    private func windowIDFromWindowList(pid: pid_t, element: AXUIElement) -> CGWindowID? {
        let axFrame = axQuartzFrame(of: element)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var matches: [(id: CGWindowID, score: CGFloat)] = []
        for entry in info {
            guard let pidNumber = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  pid_t(pidNumber.intValue) == pid
            else { continue }
            let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            guard let number = entry[kCGWindowNumber as String] as? NSNumber else { continue }
            let listFrame: CGRect
            if let bounds = entry[kCGWindowBounds as String] as? [String: Any] {
                listFrame = CGRect(
                    x: (bounds["X"] as? NSNumber)?.doubleValue ?? 0,
                    y: (bounds["Y"] as? NSNumber)?.doubleValue ?? 0,
                    width: (bounds["Width"] as? NSNumber)?.doubleValue ?? 0,
                    height: (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
                )
            } else {
                listFrame = .zero
            }
            let score = abs(listFrame.midX - axFrame.midX)
                + abs(listFrame.midY - axFrame.midY)
                + abs(listFrame.width - axFrame.width)
                + abs(listFrame.height - axFrame.height)
            matches.append((CGWindowID(number.uint32Value), score))
        }
        if matches.count == 1 {
            return matches[0].id
        }
        return matches.filter { $0.score < 16 }.min { $0.score < $1.score }?.id
    }

    private func axQuartzFrame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let positionValue = copyValue(element, kAXPositionAttribute as CFString) {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        }
        if let sizeValue = copyValue(element, kAXSizeAttribute as CFString) {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    private func cocoaFrame(of element: AXUIElement) -> CGRect {
        let quartz = axQuartzFrame(of: element)
        let cocoaOrigin = CGPoint(
            x: quartz.origin.x,
            y: primaryScreenHeight() - quartz.origin.y - quartz.height
        )
        return CGRect(origin: cocoaOrigin, size: quartz.size)
    }

    private func axOrigin(for cocoaFrame: CGRect) -> CGPoint {
        CGPoint(
            x: cocoaFrame.origin.x,
            y: primaryScreenHeight() - cocoaFrame.origin.y - cocoaFrame.height
        )
    }

    private func primaryScreenHeight() -> CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
    }

    private func copyString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        copyValue(element, attribute) as? String
    }

    private func copyValue(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        if result == .apiDisabled {
            AccessibilityTrust.requestIfUntrusted(reason: "copyValue.apiDisabled")
            return nil
        }
        guard result == .success else { return nil }
        return value
    }
}
