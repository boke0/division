import AppKit
import CoreGraphics
import DivisionKit
import Foundation

@MainActor
final class SpaceTracker {
    var onSpaceChanged: (() -> Void)?

    private let observerToken: ObserverToken

    init() {
        let token = ObserverToken()
        observerToken = token
        token.handler = { [weak self] in
            Task { @MainActor in
                self?.onSpaceChanged?()
            }
        }
    }

    func currentSpaceID(for screen: NSScreen? = NSScreen.main) -> SpaceID? {
        guard let displays = PrivateAPI.copyManagedDisplaySpaces() else { return nil }
        let displayUUID = screen.flatMap(Self.displayUUID(for:))

        let display: [String: Any]?
        if let displayUUID {
            display = displays.first { ($0["Display Identifier"] as? String) == displayUUID }
                ?? displays.first
        } else {
            display = displays.first
        }
        guard let display else { return nil }

        if let current = display["Current Space"] as? [String: Any],
           let id = Self.spaceRawID(from: current)
        {
            return SpaceID(id)
        }
        return nil
    }

    private static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        let uuidRef = uuid.takeRetainedValue()
        return CFUUIDCreateString(nil, uuidRef) as String
    }

    private static func spaceRawID(from dictionary: [String: Any]) -> UInt64? {
        if let id64 = dictionary["id64"] as? UInt64 {
            return id64
        }
        if let id64 = dictionary["id64"] as? Int {
            return UInt64(id64)
        }
        if let managed = dictionary["ManagedSpaceID"] as? UInt64 {
            return managed
        }
        if let managed = dictionary["ManagedSpaceID"] as? Int {
            return UInt64(managed)
        }
        return nil
    }
}

private final class ObserverToken: @unchecked Sendable {
    var handler: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?()
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
