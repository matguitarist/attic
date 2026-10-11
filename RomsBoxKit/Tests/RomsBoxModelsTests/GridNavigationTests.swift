import Testing
@testable import RomsBoxModels

struct GridNavigationTests {

    @Test func columnCountFitsCellsWithGaps() {
        // 3 × 160 + 2 × 20 = 520 exactly.
        #expect(GridNavigation.columnCount(availableWidth: 520, cellWidth: 160, spacing: 20) == 3)
        #expect(GridNavigation.columnCount(availableWidth: 519, cellWidth: 160, spacing: 20) == 2)
        #expect(GridNavigation.columnCount(availableWidth: 50, cellWidth: 160, spacing: 20) == 1)
    }

    @Test func emptyGridHasNothingToSelect() {
        #expect(GridNavigation.index(movingFrom: nil, direction: .right, itemCount: 0, columns: 4) == nil)
    }

    @Test func firstMoveWithNoSelectionSelectsFirstItem() {
        for direction in GridMoveDirection.allCases {
            #expect(GridNavigation.index(movingFrom: nil, direction: direction, itemCount: 10, columns: 4) == 0)
        }
    }

    @Test func staleOutOfRangeSelectionRestartsAtFirstItem() {
        #expect(GridNavigation.index(movingFrom: 42, direction: .down, itemCount: 10, columns: 4) == 0)
    }

    @Test func horizontalMovesClampAtEnds() {
        #expect(GridNavigation.index(movingFrom: 0, direction: .left, itemCount: 10, columns: 4) == 0)
        #expect(GridNavigation.index(movingFrom: 9, direction: .right, itemCount: 10, columns: 4) == 9)
        // Wraps across rows like reading order.
        #expect(GridNavigation.index(movingFrom: 3, direction: .right, itemCount: 10, columns: 4) == 4)
    }

    @Test func verticalMovesJumpByColumnCount() {
        #expect(GridNavigation.index(movingFrom: 1, direction: .down, itemCount: 10, columns: 4) == 5)
        #expect(GridNavigation.index(movingFrom: 5, direction: .up, itemCount: 10, columns: 4) == 1)
        #expect(GridNavigation.index(movingFrom: 2, direction: .up, itemCount: 10, columns: 4) == 2)
    }

    @Test func downFromColumnPastRaggedLastRowLandsOnLastItem() {
        // 10 items, 4 columns: last row holds 8 and 9 only.
        #expect(GridNavigation.index(movingFrom: 7, direction: .down, itemCount: 10, columns: 4) == 9)
        // Already on the last row: stays put.
        #expect(GridNavigation.index(movingFrom: 9, direction: .down, itemCount: 10, columns: 4) == 9)
    }
}
