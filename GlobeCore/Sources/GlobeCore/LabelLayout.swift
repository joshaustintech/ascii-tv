import Foundation

/// A place to label, already converted to a cell of the text grid.
public struct LabelMarker: Equatable, Sendable {
    public var col: Int
    public var row: Int
    public var text: String

    public init(col: Int, row: Int, text: String) {
        self.col = col
        self.row = row
        self.text = text
    }
}

/// A run of text to draw, starting at a cell.
public struct PlacedText: Equatable, Sendable {
    public var col: Int
    public var row: Int
    public var text: String
}

public enum LabelLayout {
    public static let maxLabelLength = 24

    /// Decides where each marker and its callout go so that nothing overlaps and nothing leaves the screen.
    ///
    /// Every marker gets an `o` at its own cell. Its label is tried to the right, to the left, then on the
    /// rows above and below; if none of those is free the label is dropped and only the `o` remains.
    /// Earlier markers win, so the order of the user's list is the priority order.
    /// `margin` keeps text out of the TV's overscan area.
    public static func place(_ markers: [LabelMarker], cols: Int, rows: Int,
                             margin: (cols: Int, rows: Int) = (5, 2)) -> [PlacedText] {
        var taken = Set<Int>()
        func inBounds(_ col: Int, _ row: Int, _ length: Int) -> Bool {
            row >= margin.rows && row < rows - margin.rows && col >= margin.cols && col + length <= cols - margin.cols
        }
        func isFree(_ col: Int, _ row: Int, _ length: Int) -> Bool {
            inBounds(col, row, length) && !(col..<col + length).contains { taken.contains(row * cols + $0) }
        }
        func take(_ col: Int, _ row: Int, _ length: Int) {
            for c in col..<col + length { taken.insert(row * cols + c) }
        }

        // Markers are reserved first so no label can cover another place's dot.
        var out: [PlacedText] = []
        let visible = markers.filter { $0.col >= 0 && $0.col < cols && $0.row >= 0 && $0.row < rows }
        for m in visible { take(m.col, m.row, 1) }
        for m in visible { out.append(PlacedText(col: m.col, row: m.row, text: "o")) }

        for m in visible {
            let name = String(m.text.prefix(maxLabelLength))
            guard !name.isEmpty else { continue }
            let joined = "--[ \(name) ]", joinedLeft = "[ \(name) ]--", boxed = "[ \(name) ]"
            let candidates: [(col: Int, row: Int, text: String)] = [
                (m.col + 1, m.row, joined),
                (m.col - joinedLeft.count, m.row, joinedLeft),
                (m.col + 1, m.row - 1, boxed),
                (m.col + 1, m.row + 1, boxed),
                (m.col - boxed.count, m.row - 1, boxed),
                (m.col - boxed.count, m.row + 1, boxed),
            ]
            if let c = candidates.first(where: { isFree($0.col, $0.row, $0.text.count) }) {
                take(c.col, c.row, c.text.count)
                out.append(PlacedText(col: c.col, row: c.row, text: c.text))
            }
        }
        return out
    }
}
