import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// Systems the user removed from the library. Their ROM folders stay on
/// disk, so rescans skip them until they're added back (Settings ›
/// General).
enum RemovedSystems {
    /// Comma-separated canonical ids, so `@AppStorage` can watch it.
    static let key = "removedSystems"

    static var ids: [CanonicalSystemID] {
        (UserDefaults.standard.string(forKey: key) ?? "")
            .split(separator: ",").map { CanonicalSystemID(String($0)) }
    }

    static func contains(_ id: CanonicalSystemID) -> Bool { ids.contains(id) }

    static func addBack(_ id: CanonicalSystemID) {
        store(ids.filter { $0 != id })
    }

    /// Deletes the system and its games (with their play history) from the
    /// library, and keeps rescans from bringing it back.
    static func remove(_ system: GameSystem) {
        let id = system.systemID
        if !contains(id) { store(ids + [id]) }
        let context = system.modelContext
        context?.delete(system)
        try? context?.save()
    }

    private static func store(_ ids: [CanonicalSystemID]) {
        UserDefaults.standard.set(ids.map(\.rawValue).joined(separator: ","), forKey: key)
    }
}

/// "Remove from Library…" confirmation, shared by the sidebar's menu and
/// System Settings.
struct RemoveSystemConfirmation: ViewModifier {
    @Binding var system: GameSystem?
    var onRemoved: () -> Void = {}

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Remove \(system?.displayName ?? "") from the library?",
            isPresented: Binding(get: { system != nil }, set: { if !$0 { system = nil } }),
            presenting: system
        ) { system in
            Button("Remove System", role: .destructive) {
                RemovedSystems.remove(system)
                onRemoved()
            }
        } message: { system in
            if system.gameCount == 0 {
                Text("Its ROM folder stays where it is, and rescans skip the system until you add it back in Settings › General.")
            } else {
                Text("Its \(system.gameCount) games leave Attic, along with their play history, favorites and edited info. The ROM files stay where they are, and rescans skip the system until you add it back in Settings › General.")
            }
        }
    }
}

extension View {
    func removeSystemConfirmation(_ system: Binding<GameSystem?>, onRemoved: @escaping () -> Void = {}) -> some View {
        modifier(RemoveSystemConfirmation(system: system, onRemoved: onRemoved))
    }
}
