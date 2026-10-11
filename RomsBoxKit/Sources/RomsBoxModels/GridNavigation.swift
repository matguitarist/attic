import Foundation

public enum GridMoveDirection: Sendable, Hashable, CaseIterable {
    case up, down, left, right
}

/// Pure index math for moving a selection around a row-major grid — shared
/// by arrow-key and gamepad navigation, and kept free of SwiftUI so the
/// edge cases (empty grid, ragged last row, no current selection) are
/// unit-testable.
public enum GridNavigation {

    /// How many fixed-width columns fit in `availableWidth`, matching how a
    /// row of `count` cells with `count - 1` gaps of `spacing` lays out.
    public static func columnCount(availableWidth: Double, cellWidth: Double, spacing: Double) -> Int {
        guard cellWidth > 0 else { return 1 }
        return max(1, Int(((availableWidth + spacing) / (cellWidth + spacing)).rounded(.down)))
    }

    /// The index the selection should land on after one move, or `nil`
    /// when there's nothing to select. With no current selection, any move
    /// selects the first item rather than doing nothing — the first press
    /// on a freshly opened grid should visibly *do* something.
    public static func index(
        movingFrom current: Int?,
        direction: GridMoveDirection,
        itemCount: Int,
        columns: Int
    ) -> Int? {
        guard itemCount > 0 else { return nil }
        guard let current, (0..<itemCount).contains(current) else { return 0 }
        let columns = max(1, columns)

        switch direction {
        case .left:
            return max(0, current - 1)
        case .right:
            return min(itemCount - 1, current + 1)
        case .up:
            let target = current - columns
            return target >= 0 ? target : current
        case .down:
            let target = current + columns
            if target < itemCount { return target }
            // Ragged last row: from a column the last row doesn't reach,
            // drop onto the last item (as Finder does) instead of getting
            // stuck one row short of the end.
            let lastRow = (itemCount - 1) / columns
            return current / columns < lastRow ? itemCount - 1 : current
        }
    }
}
