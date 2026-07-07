import SwiftUI
import RomsBoxPersistence

/// Custom sidebar rows rather than `List(selection:)` — the latter proved
/// unreliable at actually changing selection on click in this app (rows
/// highlighted inconsistently and sometimes never updated the grid), and a
/// plain-Button implementation both fixes that outright and gives full
/// control over the Liquid Glass selection styling.
struct LibrarySidebarView: View {
    let systems: [GameSystem]
    @Binding var selection: LibrarySelection?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 4) {
                VStack(alignment: .leading, spacing: 20) {
                    sidebarSection(title: "Library") {
                        row(icon: "square.grid.2x2", title: "All Games", value: .allGames)
                        row(icon: "star.fill", title: "Favorites", value: .favorites)
                        row(icon: "clock", title: "Recently Played", value: .recentlyPlayed)
                    }

                    if !systems.isEmpty {
                        sidebarSection(title: "Systems") {
                            ForEach(systems) { system in
                                row(
                                    icon: "square.stack",
                                    title: system.displayName,
                                    value: .system(system.systemID),
                                    count: system.games.count
                                )
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("RomsBox")
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            content()
        }
    }

    private func row(icon: String, title: String, value: LibrarySelection, count: Int? = nil) -> some View {
        let isSelected = selection == value

        return Button {
            selection = value
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .glassEffect(
            isSelected ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}
