import Foundation

/// Digit-buffer matching and confirmation for the window switcher.
///
/// Window numbers are 1-based (`1...count`). A typed buffer matches by decimal
/// prefix: `"1"` matches 1, 10, 11, …; `"10"` matches 10, 100, ….
public enum SwitcherInput {
    /// Parses a digit buffer into a 1-based window number.
    public static func number(fromBuffer buffer: String) -> Int? {
        guard !buffer.isEmpty, buffer.allSatisfy(\.isNumber), let value = Int(buffer), value >= 1 else {
            return nil
        }
        return value
    }

    /// 0-based order indices whose 1-based labels have `buffer` as a prefix.
    /// An empty buffer matches every index.
    public static func matchingIndices(buffer: String, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        if buffer.isEmpty {
            return Array(0..<count)
        }
        guard buffer.allSatisfy(\.isNumber) else { return [] }
        return (0..<count).filter { index in
            String(index + 1).hasPrefix(buffer)
        }
    }

    /// 0-based index of an exact 1-based number, if it exists.
    public static func exactIndex(buffer: String, count: Int) -> Int? {
        guard let number = number(fromBuffer: buffer) else { return nil }
        let index = number - 1
        return (0..<count).contains(index) ? index : nil
    }

    /// Index to raise on Enter, or `nil` when the buffer matches nothing.
    ///
    /// Empty buffer confirms `highlighted` when it is in range, otherwise the first item.
    /// A non-empty buffer confirms the highlighted match, or the first prefix match.
    public static func confirmIndex(buffer: String, highlighted: Int?, count: Int) -> Int? {
        let matches = matchingIndices(buffer: buffer, count: count)
        guard !matches.isEmpty else { return nil }
        if let highlighted, matches.contains(highlighted) {
            return highlighted
        }
        return matches[0]
    }
}

/// Mutable digit buffer and highlight for one switcher presentation.
public struct SwitcherSession: Equatable, Sendable {
    public var count: Int
    public var buffer: String
    /// 0-based index into the full list.
    public var highlighted: Int?

    public init(count: Int, buffer: String = "", highlighted: Int? = nil) {
        self.count = max(0, count)
        self.buffer = Self.digits(in: buffer)
        self.highlighted = highlighted
        snapHighlight(preferring: highlighted)
    }

    public var matchingIndices: [Int] {
        SwitcherInput.matchingIndices(buffer: buffer, count: count)
    }

    public func confirmIndex() -> Int? {
        SwitcherInput.confirmIndex(buffer: buffer, highlighted: highlighted, count: count)
    }

    public mutating func appendDigit(_ character: Character) {
        guard let value = character.wholeNumberValue, (0...9).contains(value) else {
            return
        }
        buffer.append(contentsOf: String(value))
        snapHighlight(preferring: highlighted)
    }

    public mutating func deleteLastDigit() {
        guard !buffer.isEmpty else { return }
        buffer.removeLast()
        snapHighlight(preferring: highlighted)
    }

    public mutating func moveHighlight(by offset: Int) {
        let matches = matchingIndices
        guard !matches.isEmpty, offset != 0 else { return }
        let current = highlighted.flatMap { matches.firstIndex(of: $0) } ?? 0
        let next = (current + offset % matches.count + matches.count) % matches.count
        highlighted = matches[next]
    }

    public mutating func updateCount(_ newCount: Int) {
        count = max(0, newCount)
        if let highlighted, !(0..<count).contains(highlighted) {
            self.highlighted = nil
        }
        snapHighlight(preferring: highlighted)
    }

    public mutating func preferHighlight(_ index: Int) {
        snapHighlight(preferring: index)
    }

    private mutating func snapHighlight(preferring preferred: Int?) {
        let matches = matchingIndices
        guard !matches.isEmpty else {
            highlighted = nil
            return
        }
        if let preferred, matches.contains(preferred) {
            highlighted = preferred
        } else {
            highlighted = matches[0]
        }
    }

    private static func digits(in string: String) -> String {
        String(string.filter { $0.isNumber })
    }
}
