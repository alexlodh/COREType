import Foundation

/// Maps extended-grapheme positions to the UTF-16 ranges used by NSTextStorage.
/// Only the typed prefix can display replacement glyphs. The untyped suffix
/// therefore shares the source offsets with one constant displacement.
public struct PassageUTF16Map {
    private let sourceOffsets: [Int]
    private var typedOffsets: [Int] = [0]

    public var graphemeCount: Int { sourceOffsets.count - 1 }
    public var typedCount: Int { typedOffsets.count - 1 }
    public var utf16Count: Int { offset(at: graphemeCount) }

    public init(target: [Character]) {
        var offsets = [0]
        offsets.reserveCapacity(target.count + 1)
        for character in target {
            offsets.append(offsets.last! + String(character).utf16.count)
        }
        sourceOffsets = offsets
        typedOffsets.reserveCapacity(target.count + 1)
    }

    /// Replace a suffix of the displayed typed prefix. Appending and deleting
    /// its last grapheme touch no offsets in the remaining source passage.
    public mutating func replaceTypedSuffix(from start: Int, displayed: [Character]) {
        precondition(start >= 0 && start <= typedCount)
        precondition(start + displayed.count <= graphemeCount)
        typedOffsets.removeSubrange((start + 1)..<typedOffsets.count)
        for character in displayed {
            typedOffsets.append(typedOffsets.last! + String(character).utf16.count)
        }
    }

    public func offset(at grapheme: Int) -> Int {
        precondition(grapheme >= 0 && grapheme <= graphemeCount)
        if grapheme <= typedCount { return typedOffsets[grapheme] }
        return sourceOffsets[grapheme] + typedOffsets.last! - sourceOffsets[typedCount]
    }

    public func range(at grapheme: Int) -> NSRange {
        precondition(grapheme >= 0 && grapheme < graphemeCount)
        return range(in: grapheme..<(grapheme + 1))
    }

    public func range(in graphemes: Range<Int>) -> NSRange {
        precondition(graphemes.lowerBound >= 0 && graphemes.upperBound <= graphemeCount)
        let start = offset(at: graphemes.lowerBound)
        return NSRange(location: start, length: offset(at: graphemes.upperBound) - start)
    }
}
