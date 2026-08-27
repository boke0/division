import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

enum PrivateAPI {
    static func mainConnectionID() -> Int32 {
        CGSMainConnectionID()
    }

    static func copyManagedDisplaySpaces() -> [[String: Any]]? {
        let cid = CGSMainConnectionID()
        guard let unmanaged = CGSCopyManagedDisplaySpaces(cid) else { return nil }
        let array = unmanaged.takeRetainedValue()
        return array as? [[String: Any]]
    }

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        var identifier: CGWindowID = 0
        let error = _AXUIElementGetWindow(element, &identifier)
        guard error == .success, identifier != 0 else { return nil }
        return identifier
    }

    /// Best-effort move of `windowID` onto `spaceID`. Tries SkyLight's bridged
    /// operation, then `SLSMoveWindowsToManagedSpace`. Returns whether a call
    /// was issued; the WindowServer may still no-op on some OS versions.
    @discardableResult
    static func moveWindow(_ windowID: CGWindowID, toSpace spaceID: UInt64) -> Bool {
        _ = loadSkyLight()
        let windows = [NSNumber(value: windowID)] as NSArray
        if performBridgedMove(windows, to: spaceID) {
            return true
        }
        return slsMoveWindows(windows, to: spaceID)
    }

    private static func loadSkyLight() -> UnsafeMutableRawPointer? {
        dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY
        )
    }

    private static func slsMoveWindows(_ windows: NSArray, to spaceID: UInt64) -> Bool {
        typealias MoveFn = @convention(c) (Int32, CFArray, UInt64) -> Void
        guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "SLSMoveWindowsToManagedSpace")
            ?? loadSkyLight().flatMap({ dlsym($0, "SLSMoveWindowsToManagedSpace") })
        else {
            return false
        }
        let move = unsafeBitCast(symbol, to: MoveFn.self)
        move(CGSMainConnectionID(), windows, spaceID)
        return true
    }

    private static func performBridgedMove(_ windows: NSArray, to spaceID: UInt64) -> Bool {
        guard let operationClass = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") as? NSObject.Type
        else {
            return false
        }
        let initializer = NSSelectorFromString("initWithWindows:spaceID:")
        guard operationClass.instancesRespond(to: initializer),
              let objc_msgSend = dlsym(dlopen(nil, RTLD_LAZY), "objc_msgSend")
        else {
            return false
        }

        typealias Allocate = @convention(c) (AnyClass, Selector) -> AnyObject?
        let allocate = unsafeBitCast(objc_msgSend, to: Allocate.self)
        guard let allocated = allocate(operationClass, NSSelectorFromString("alloc")) else {
            return false
        }

        typealias InitMove = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> AnyObject?
        let initMove = unsafeBitCast(objc_msgSend, to: InitMove.self)
        guard let operation = initMove(allocated, initializer, windows, spaceID) else {
            return false
        }

        let perform = NSSelectorFromString("performWithWMBridgeDelegate")
        guard operation.responds(to: perform) else {
            return false
        }
        typealias PerformMove = @convention(c) (AnyObject, Selector) -> AnyObject?
        let performMove = unsafeBitCast(objc_msgSend, to: PerformMove.self)
        _ = performMove(operation, perform)
        return true
    }
}

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError
