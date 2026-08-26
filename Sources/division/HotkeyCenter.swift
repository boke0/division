import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import DivisionKit
import Foundation
import os

enum DivisionLog {
    private static let logger = Logger(subsystem: "com.boke0.division", category: "hotkey")

    static func event(_ message: String) {
        NSLog("%@", message)
        logger.notice("\(message, privacy: .public)")
        let line = message + "\n"
        let path = "/tmp/division-hotkeys.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }
}

struct HotkeyFocusSnapshot: Sendable {
    var axPID: pid_t?
    var axName: String
    var workspacePID: pid_t?
    var workspaceName: String
    var uptime: TimeInterval
}

/// Carbon hotkeys, same shape as Summon's `HotkeyCenter`: one `InstallEventHandler`,
/// `RegisterEventHotKey` per binding, handler extracts `EventHotKeyID`, main-queue callback.
/// CGEvent tap is only for bindings Carbon refused (for example Tab).
final class HotkeyCenter: @unchecked Sendable {
    static let shared = HotkeyCenter()

    var onPressed: (@MainActor (UInt32) -> Void)?

    private let lock = NSLock()
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var tapBindings: [HotkeyAction: Hotkey] = [:]
    private var consumedKeyCodes: Set<UInt32> = []
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var lastFocusSnapshot: HotkeyFocusSnapshot?
    private let signature: OSType = 0x44495631 // 'DIV1'

    private init() {}

    func recentFocusSnapshot(maxAge: TimeInterval = 1.0) -> HotkeyFocusSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let lastFocusSnapshot else { return nil }
        guard ProcessInfo.processInfo.systemUptime - lastFocusSnapshot.uptime <= maxAge else {
            return nil
        }
        return lastFocusSnapshot
    }

    func register(_ bindings: [HotkeyAction: Hotkey]) {
        unregisterCarbonHotKeys()
        lock.lock()
        tapBindings.removeAll()
        consumedKeyCodes.removeAll()
        lock.unlock()

        installHandlerIfNeeded()

        var leftovers: [HotkeyAction: Hotkey] = [:]
        for (action, hotkey) in bindings.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: action.rawValue)
            let status = RegisterEventHotKey(
                hotkey.carbonKeyCode,
                hotkey.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            DivisionLog.event(
                "division: RegisterEventHotKey action=\(action) key=0x\(String(hotkey.carbonKeyCode, radix: 16)) mods=0x\(String(hotkey.carbonModifiers, radix: 16)) status=\(status)"
            )
            if status == noErr, let ref {
                hotKeyRefs[action.rawValue] = ref
            } else {
                leftovers[action] = hotkey
            }
        }

        if leftovers.isEmpty {
            removeTap()
            removeMonitors()
            DivisionLog.event("division: all \(bindings.count) hotkeys registered via Carbon")
            return
        }

        lock.lock()
        tapBindings = leftovers
        lock.unlock()
        DivisionLog.event(
            "division: Carbon leftovers for tap: \(leftovers.keys.map { String(describing: $0) }.sorted().joined(separator: ","))"
        )
        installTapIfNeeded()
    }

    func unregisterAll() {
        unregisterCarbonHotKeys()
        lock.lock()
        tapBindings.removeAll()
        consumedKeyCodes.removeAll()
        lock.unlock()
        removeTap()
        removeMonitors()
    }

    private func unregisterCarbonHotKeys() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            divisionCarbonHotkeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &ref
        )
        if status != noErr {
            DivisionLog.event("division: InstallEventHandler failed (\(status))")
            return
        }
        handlerRef = ref
        DivisionLog.event("division: Carbon hotkey handler installed")
    }

    private func installTapIfNeeded() {
        if let tap, CGEvent.tapIsEnabled(tap: tap) {
            DivisionLog.event("division: event tap already enabled")
            return
        }
        removeTap()

        let mask: CGEventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: divisionEventTapCallback,
            userInfo: userInfo
        ) else {
            DivisionLog.event("division: CGEvent tap create failed; trying NSEvent monitors")
            installMonitorsIfNeeded()
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            DivisionLog.event("division: CGEvent tap run loop source failed")
            installMonitorsIfNeeded()
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        removeMonitors()
        DivisionLog.event("division: event tap installed (session/defaultTap)")
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func installMonitorsIfNeeded() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event) == true ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            _ = self?.handleNSEvent(event)
        }
        DivisionLog.event(
            "division: NSEvent monitors installed local=\(localMonitor != nil) global=\(globalMonitor != nil)"
        )
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
    }

    fileprivate func handleCarbonPress(id: UInt32) {
        captureFocusSnapshot()
        let name = HotkeyAction(rawValue: id).map { String(describing: $0) } ?? "id:\(id)"
        DivisionLog.event("division: carbon matched \(name)")
        handlePress(id: id, alreadySnapshotted: true)
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                DivisionLog.event("division: event tap re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
        let matched = matchTapBinding(keyCode: keyCode, eventFlags: flags)

        if type == .keyUp {
            lock.lock()
            let consumed = consumedKeyCodes.remove(keyCode) != nil
            lock.unlock()
            return consumed ? nil : Unmanaged.passUnretained(event)
        }

        lock.lock()
        let alreadyConsumed = consumedKeyCodes.contains(keyCode)
        lock.unlock()

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            if matched != nil || alreadyConsumed {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard let action = matched else {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        consumedKeyCodes.insert(keyCode)
        lock.unlock()
        DivisionLog.event("division: tap matched \(action)")
        handlePress(id: action.rawValue)
        return nil
    }

    private func handleNSEvent(_ event: NSEvent) -> Bool {
        let keyCode = UInt32(event.keyCode)
        let flags = UInt64(event.modifierFlags.rawValue)

        if event.type == .keyUp {
            lock.lock()
            let consumed = consumedKeyCodes.remove(keyCode) != nil
            lock.unlock()
            return consumed
        }

        let matched = matchTapBinding(keyCode: keyCode, eventFlags: flags)
        lock.lock()
        let alreadyConsumed = consumedKeyCodes.contains(keyCode)
        lock.unlock()

        if event.isARepeat {
            return matched != nil || alreadyConsumed
        }

        guard let action = matched else { return false }
        lock.lock()
        consumedKeyCodes.insert(keyCode)
        lock.unlock()
        DivisionLog.event("division: nsevent matched \(action)")
        handlePress(id: action.rawValue)
        return true
    }

    private func matchTapBinding(keyCode: UInt32, eventFlags: UInt64) -> HotkeyAction? {
        lock.lock()
        let snapshot = tapBindings
        lock.unlock()
        return HotkeyMatcher.matchingAction(
            keyCode: keyCode,
            eventFlags: eventFlags,
            bindings: snapshot
        )
    }

    private func handlePress(id: UInt32, alreadySnapshotted: Bool = false) {
        if !alreadySnapshotted {
            captureFocusSnapshot()
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPressed?(id)
        }
    }

    fileprivate func captureFocusSnapshot() {
        var axPID: pid_t?
        var axName = "nil"
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        if error == .success, let value {
            var pid: pid_t = 0
            if AXUIElementGetPid(value as! AXUIElement, &pid) == .success {
                axPID = pid
                axName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid=\(pid)"
            } else {
                axName = "pid-error"
            }
        } else {
            axName = "axError=\(error.rawValue)"
        }
        let workspace = NSWorkspace.shared.frontmostApplication
        let snapshot = HotkeyFocusSnapshot(
            axPID: axPID,
            axName: axName,
            workspacePID: workspace?.processIdentifier,
            workspaceName: workspace?.localizedName ?? "nil",
            uptime: ProcessInfo.processInfo.systemUptime
        )
        lock.lock()
        lastFocusSnapshot = snapshot
        lock.unlock()
        DivisionLog.event(
            "division: hotkey snapshot axApp=\(snapshot.axName) workspaceFrontmost=\(snapshot.workspaceName)"
        )
    }
}

private func divisionCarbonHotkeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DivisionLog.event("division: carbon handler invoked")
    guard let userData else {
        DivisionLog.event("division: carbon handler missing userData")
        return OSStatus(eventNotHandledErr)
    }
    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    guard let event else {
        DivisionLog.event("division: carbon handler event is nil")
        return OSStatus(eventNotHandledErr)
    }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else {
        DivisionLog.event("division: GetEventParameter failed (\(status))")
        return status
    }
    center.handleCarbonPress(id: hotKeyID.id)
    return noErr
}

private func divisionEventTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotkeyCenter>.fromOpaque(refcon).takeUnretainedValue()
        .handleEvent(type: type, event: event)
}
