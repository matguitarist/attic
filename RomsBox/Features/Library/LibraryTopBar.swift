import SwiftUI

/// A dedicated top bar for the library grid — search on the left, sort on
/// the right — kept as its own strip above the grid rather than relying on
/// the window's automatic toolbar/`.searchable` placement, so it stays in
/// one consistent place regardless of selection or window state.
struct LibraryTopBar: View {
    @Binding var searchText: String
    @Binding var sortOrder: GameSortOrder

    var body: some View {
        HStack(spacing: 12) {
            searchField
            Spacer(minLength: 12)
            sortMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
            Text(sortOrder.label)
                .frame(minWidth: 110)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.glass)
    }
}
