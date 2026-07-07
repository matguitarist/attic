import SwiftUI

/// A dedicated top bar for the library grid — search on the left, sort on
/// the right — kept as its own strip above the grid rather than relying on
/// the window's automatic toolbar/`.searchable` placement, so it stays in
/// one consistent place regardless of selection or window state.
struct LibraryTopBar: View {
    @Binding var searchText: String
    @Binding var sortOrder: GameSortOrder
    @Binding var cellScale: Double

    static let cellScaleRange: ClosedRange<Double> = 0.6...1.8

    var body: some View {
        HStack(spacing: 12) {
            searchField
            Spacer(minLength: 12)
            zoomSlider
            sortMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var zoomSlider: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: $cellScale, in: Self.cellScaleRange)
                .tint(.accentColor)
                .frame(width: 100)
            Image(systemName: "photo")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
        .help("Cover art size")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: 280)
    }

    /// Built with the exact same padding/shape/glass treatment as
    /// `searchField` (rather than `.buttonStyle(.glass)`, whose own
    /// built-in padding and corner radius don't match a `Capsule()`) so
    /// the two pills in this bar are visually identical.
    private var sortMenu: some View {
        Menu {
            ForEach(GameSortOrder.allCases) { order in
                Button {
                    sortOrder = order
                } label: {
                    if order == sortOrder {
                        Label(order.label, systemImage: "checkmark")
                    } else {
                        Text(order.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(sortOrder.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 100)
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
    }
}
