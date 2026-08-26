import Testing
@testable import DivisionKit

@Test func parseBufferToOneBasedNumber() {
    #expect(SwitcherInput.number(fromBuffer: "1") == 1)
    #expect(SwitcherInput.number(fromBuffer: "9") == 9)
    #expect(SwitcherInput.number(fromBuffer: "12") == 12)
    #expect(SwitcherInput.number(fromBuffer: "10") == 10)
    #expect(SwitcherInput.number(fromBuffer: "") == nil)
    #expect(SwitcherInput.number(fromBuffer: "0") == nil)
    #expect(SwitcherInput.number(fromBuffer: "a") == nil)
}

@Test func matchingIndicesEmptyBufferMatchesAll() {
    #expect(SwitcherInput.matchingIndices(buffer: "", count: 12) == Array(0..<12))
    #expect(SwitcherInput.matchingIndices(buffer: "", count: 0) == [])
}

@Test func matchingIndicesPrefixOneDigitAndTwoDigit() {
    #expect(SwitcherInput.matchingIndices(buffer: "1", count: 12) == [0, 9, 10, 11])
    #expect(SwitcherInput.matchingIndices(buffer: "10", count: 12) == [9])
    #expect(SwitcherInput.matchingIndices(buffer: "12", count: 12) == [11])
    #expect(SwitcherInput.matchingIndices(buffer: "2", count: 12) == [1])
    #expect(SwitcherInput.matchingIndices(buffer: "3", count: 5) == [2])
}

@Test func matchingIndicesInvalidBuffer() {
    #expect(SwitcherInput.matchingIndices(buffer: "0", count: 12) == [])
    #expect(SwitcherInput.matchingIndices(buffer: "99", count: 12) == [])
    #expect(SwitcherInput.matchingIndices(buffer: "13", count: 12) == [])
}

@Test func exactIndexResolvesOneBasedNumber() {
    #expect(SwitcherInput.exactIndex(buffer: "1", count: 12) == 0)
    #expect(SwitcherInput.exactIndex(buffer: "10", count: 12) == 9)
    #expect(SwitcherInput.exactIndex(buffer: "12", count: 12) == 11)
    #expect(SwitcherInput.exactIndex(buffer: "13", count: 12) == nil)
    #expect(SwitcherInput.exactIndex(buffer: "", count: 12) == nil)
}

@Test func confirmIndexEmptyBufferUsesHighlightOrFirst() {
    #expect(SwitcherInput.confirmIndex(buffer: "", highlighted: nil, count: 5) == 0)
    #expect(SwitcherInput.confirmIndex(buffer: "", highlighted: 3, count: 5) == 3)
    #expect(SwitcherInput.confirmIndex(buffer: "", highlighted: 0, count: 0) == nil)
    #expect(SwitcherInput.confirmIndex(buffer: "", highlighted: 9, count: 5) == 0)
}

@Test func confirmIndexUniqueMatchStillNeedsExplicitConfirm() {
    #expect(SwitcherInput.confirmIndex(buffer: "3", highlighted: 2, count: 5) == 2)
    #expect(SwitcherInput.confirmIndex(buffer: "2", highlighted: 1, count: 12) == 1)
    #expect(SwitcherInput.confirmIndex(buffer: "12", highlighted: 11, count: 12) == 11)
}

@Test func confirmIndexAmbiguousUsesHighlightedMatch() {
    #expect(SwitcherInput.confirmIndex(buffer: "1", highlighted: 0, count: 12) == 0)
    #expect(SwitcherInput.confirmIndex(buffer: "1", highlighted: 9, count: 12) == 9)
    #expect(SwitcherInput.confirmIndex(buffer: "1", highlighted: 11, count: 12) == 11)
}

@Test func confirmIndexInvalidKeepsNil() {
    #expect(SwitcherInput.confirmIndex(buffer: "99", highlighted: 0, count: 12) == nil)
    #expect(SwitcherInput.confirmIndex(buffer: "0", highlighted: 0, count: 12) == nil)
}

@Test func sessionAppendsDigitsAndConfirmsPrefixMatch() {
    var session = SwitcherSession(count: 12)
    #expect(session.highlighted == 0)

    session.appendDigit("1")
    #expect(session.buffer == "1")
    #expect(session.matchingIndices == [0, 9, 10, 11])
    #expect(session.highlighted == 0)
    #expect(session.confirmIndex() == 0)

    session.appendDigit("0")
    #expect(session.buffer == "10")
    #expect(session.matchingIndices == [9])
    #expect(session.highlighted == 9)
    #expect(session.confirmIndex() == 9)
}

@Test func sessionBackspaceRestoresPrefixMatches() {
    var session = SwitcherSession(count: 12)
    session.appendDigit("1")
    session.appendDigit("2")
    #expect(session.confirmIndex() == 11)

    session.deleteLastDigit()
    #expect(session.buffer == "1")
    #expect(session.matchingIndices == [0, 9, 10, 11])
}

@Test func sessionMoveHighlightAmongMatches() {
    var session = SwitcherSession(count: 12)
    session.appendDigit("1")
    session.moveHighlight(by: 1)
    #expect(session.highlighted == 9)
    session.moveHighlight(by: 1)
    #expect(session.highlighted == 10)
    session.moveHighlight(by: -1)
    #expect(session.highlighted == 9)
    session.moveHighlight(by: -1)
    #expect(session.highlighted == 0)
    session.moveHighlight(by: -1)
    #expect(session.highlighted == 11)
}

@Test func sessionEmptyBufferEnterConfirmsHighlight() {
    var session = SwitcherSession(count: 8)
    session.moveHighlight(by: 2)
    #expect(session.buffer.isEmpty)
    #expect(session.confirmIndex() == 2)
}
