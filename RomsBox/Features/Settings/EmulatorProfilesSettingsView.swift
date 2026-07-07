import SwiftUI
import SwiftData
import RomsBoxModels
import RomsBoxPersistence

struct EmulatorProfilesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]

    @State private var editingProfile: EmulatorProfile?
    @State private var isPresentingNewProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "No Custom Emulators",
                    systemImage: "gamecontroller",
                    description: Text("Add a standalone emulator to launch specific systems or games with instead of RetroArch.")
                )
            } else {
                List(profiles) { profile in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name).font(.headline)
                        Text(profile.executablePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !profile.assignedSystemIDs.isEmpty {
                            Text(profile.assignedSystemIDs.compactMap { SystemTaxonomy.definition(for: $0)?.displayName }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingProfile = profile }
                    .swipeActions {
                        Button(role: .destructive) {
                            modelContext.delete(profile)
                            try? modelContext.save()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Button("Add Custom Emulator…") { isPresentingNewProfile = true }
        }
        .padding(20)
        .frame(width: 460, height: 360)
        .sheet(isPresented: $isPresentingNewProfile) {
            EmulatorProfileEditorView(
                title: "New Custom Emulator",
                name: "",
                executablePath: "",
                argumentTemplate: "{romPath}",
                assignedSystemIDs: [],
                onSave: { name, path, template, systems in
                    let profile = EmulatorProfile(
                        name: name,
                        executableURL: URL(fileURLWithPath: path),
                        argumentTemplate: template,
                        assignedSystemIDs: Array(systems)
                    )
                    modelContext.insert(profile)
                    try? modelContext.save()
                    isPresentingNewProfile = false
                },
                onCancel: { isPresentingNewProfile = false }
            )
        }
        .sheet(item: $editingProfile) { profile in
            EmulatorProfileEditorView(
                title: "Edit Custom Emulator",
                name: profile.name,
                executablePath: profile.executablePath,
                argumentTemplate: profile.argumentTemplate,
                assignedSystemIDs: Set(profile.assignedSystemIDs),
                onSave: { name, path, template, systems in
                    profile.name = name
                    profile.executablePath = path
                    profile.argumentTemplate = template
                    profile.assignedSystemIDs = Array(systems)
                    try? modelContext.save()
                    editingProfile = nil
                },
                onCancel: { editingProfile = nil }
            )
        }
    }
}
