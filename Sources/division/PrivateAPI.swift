import ApplicationServices
import CoreGraphics
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
