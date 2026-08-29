import Foundation

/// Rules for windows that look like AX standard windows but must not be tiled.
public enum WindowEligibility: Sendable {
    /// Chrome video PiP uses `"Picture in Picture"`; document PiP / Firefox / YouTube use `"Picture-in-Picture"`.
    public static func isPictureInPictureTitle(_ title: String) -> Bool {
        pipTitleKeys.contains(compactTitle(title))
    }

    /// Normal application windows sit at `kCGNormalWindowLevel` (layer 0). Overlay PiP is keep-on-top.
    public static func isNormalWindowLayer(_ layer: Int) -> Bool {
        layer == 0
    }

    public static func shouldTile(title: String, layer: Int?) -> Bool {
        if isPictureInPictureTitle(title) {
            return false
        }
        if let layer, !isNormalWindowLayer(layer) {
            return false
        }
        return true
    }

    private static func compactTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined()
    }

    private static let pipTitleKeys: Set<String> = [
        "pictureinpicture",
        "ピクチャーインピクチャー",
        "ピクチャインピクチャ",
    ]
}
