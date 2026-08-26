import ApplicationServices
import Darwin
import Foundation
import Security

/// TCC Accessibility client for this process.
///
/// Swift 6 imports `kAXTrustedCheckOptionPrompt` as `Unmanaged<CFString>` and
/// rejects a direct reference (`shared mutable state`). A Swift `Dictionary`
/// keyed by `String` then `as CFDictionary` can fail to match the CF global
/// that `AXIsProcessTrustedWithOptions` looks up, so TCC never attaches to
/// *this* signature while System Settings still shows an older "Division" row.
@MainActor
enum AccessibilityTrust {
    private static var lastPromptAt: Date?

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt TCC using the real CFString option key and `kCFBooleanTrue`.
    @discardableResult
    static func requestIfUntrusted(reason: String, force: Bool = false) -> Bool {
        if AXIsProcessTrusted() { return true }
        if !force, let last = lastPromptAt, Date().timeIntervalSince(last) < 8 {
            return false
        }
        lastPromptAt = Date()
        let options = promptOptions()
        let after = AXIsProcessTrustedWithOptions(options)
        let optionsDesc = CFCopyDescription(options) as String? ?? "?"
        DivisionLog.event(
            "division: AX TCC request reason=\(reason) after=\(after) options=\(optionsDesc) \(identityDescription())"
        )
        return after
    }

    static func identityDescription() -> String {
        let bundle = Bundle.main
        let path = bundle.bundlePath
        let identifier = bundle.bundleIdentifier ?? "(nil)"
        let exec = bundle.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "(nil)"
        return "bundle=\(identifier) path=\(path) exec=\(exec) \(signingDescription())"
    }

    /// `kAXTrustedCheckOptionPrompt` as CFString, not a Swift `String` dict key.
    private static func promptOptions() -> CFDictionary {
        let key = promptKey()
        let dict = NSMutableDictionary()
        dict.setObject(kCFBooleanTrue as Any, forKey: key)
        return dict
    }

    private static func promptKey() -> NSString {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        if let symbol = dlsym(rtldDefault, "kAXTrustedCheckOptionPrompt") {
            let cf = symbol.assumingMemoryBound(to: Unmanaged<CFString>.self)
                .pointee
                .takeUnretainedValue()
            return cf as NSString
        }
        return "AXTrustedCheckOptionPrompt" as NSString
    }

    private static func signingDescription() -> String {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
            return "csreq=unreadable cdhash=unreadable"
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else {
            return "csreq=unreadable cdhash=unreadable"
        }
        var requirement: SecRequirement?
        var reqText = "unreadable"
        if SecCodeCopyDesignatedRequirement(staticCode, SecCSFlags(), &requirement) == errSecSuccess,
           let requirement
        {
            var string: CFString?
            if SecRequirementCopyString(requirement, SecCSFlags(), &string) == errSecSuccess,
               let string
            {
                reqText = string as String
            }
        }
        var cdhash = "unreadable"
        var info: CFDictionary?
        if SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        ) == errSecSuccess,
            let info = info as NSDictionary?,
            let unique = info[kSecCodeInfoUnique] as? Data
        {
            cdhash = unique.map { String(format: "%02x", $0) }.joined()
        }
        return "csreq=\(reqText) cdhash=\(cdhash)"
    }
}
