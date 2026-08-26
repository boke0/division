import AppKit
import ApplicationServices
import DivisionKit
import Foundation

final class WindowObserver: @unchecked Sendable {
    var onWindowCreated: ((WindowID) -> Void)?
    var onWindowsChanged: (() -> Void)?
    var onFocusChanged: (() -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    private var ownPID: pid_t {
        ProcessInfo.processInfo.processIdentifier
    }

    func start() {
        stop()
        for app in NSWorkspace.shared.runningApplications {
            addObserver(for: app)
        }

        let center = NSWorkspace.shared.notificationCenter
        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.addObserver(for: app)
        }
        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.removeObserver(pid: app.processIdentifier)
            self?.emitWindowsChanged()
        }
        activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.emitFocusChanged()
        }
    }

    func stop() {
        for pid in observers.keys {
            removeObserver(pid: pid)
        }
        let center = NSWorkspace.shared.notificationCenter
        if let launchObserver { center.removeObserver(launchObserver) }
        if let terminateObserver { center.removeObserver(terminateObserver) }
        if let activateObserver { center.removeObserver(activateObserver) }
        launchObserver = nil
        terminateObserver = nil
        activateObserver = nil
    }

    deinit {
        stop()
    }

    private func addObserver(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ownPID, app.activationPolicy == .regular, observers[pid] == nil else { return }

        var observer: AXObserver?
        let error = AXObserverCreate(pid, divisionAXObserverCallback, &observer)
        guard error == .success, let observer else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)
        _ = AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
        _ = AXObserverAddNotification(observer, appElement, kAXFocusedWindowChangedNotification as CFString, refcon)
        _ = AXObserverAddNotification(observer, appElement, kAXApplicationActivatedNotification as CFString, refcon)

        if let windows = copyWindows(appElement) {
            for window in windows {
                _ = AXObserverAddNotification(
                    observer,
                    window,
                    kAXUIElementDestroyedNotification as CFString,
                    refcon
                )
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func removeObserver(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    fileprivate func handle(element: AXUIElement, notification: String) {
        if notification == (kAXWindowCreatedNotification as String) {
            resolveCreated(element, attempt: 0)
        } else if notification == (kAXFocusedWindowChangedNotification as String)
            || notification == (kAXApplicationActivatedNotification as String)
        {
            emitFocusChanged()
        } else if notification == (kAXUIElementDestroyedNotification as String) {
            emitWindowsChanged()
        }
    }

    private func resolveCreated(_ element: AXUIElement, attempt: Int) {
        if let cgID = PrivateAPI.windowID(for: element) {
            emitCreated(WindowID(cgID))
            return
        }
        guard attempt < 6 else { return }
        let box = AXElementBox(element)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(attempt + 1)) { [weak self] in
            self?.resolveCreated(box.element, attempt: attempt + 1)
        }
    }

    private func emitCreated(_ id: WindowID) {
        DispatchQueue.main.async { [weak self] in
            self?.onWindowCreated?(id)
        }
    }

    private func emitFocusChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.onFocusChanged?()
        }
    }

    private func emitWindowsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.onWindowsChanged?()
        }
    }

    private func copyWindows(_ appElement: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? [AXUIElement]
    }
}

private func divisionAXObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let watcher = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String

    if name == (kAXWindowCreatedNotification as String) {
        _ = AXObserverAddNotification(
            observer,
            element,
            kAXUIElementDestroyedNotification as CFString,
            refcon
        )
    }

    let box = AXElementBox(element)
    DispatchQueue.main.async {
        watcher.handle(element: box.element, notification: name)
    }
}

private final class AXElementBox: @unchecked Sendable {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }
}
