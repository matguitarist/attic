import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence

/// The Custom Emulators section of Settings › Emulators: standalone
/// emulators the user set up by hand, to launch systems or single games
/// with instead of RetroArch.
struct CustomEmulatorsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmulatorProfile.name) private var profiles: [EmulatorProfile]

    @State private var editingProfile: EmulatorProfile?
    @State private var isPresentingNewProfile = false

    var body: some View {
        Section {
            ForEach(profiles) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
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
                    Spacer()
                    Button("Edit…") { editingProfile = profile }
                    Button(role: .destructive) {
                        modelContext.delete(profile)
                        try? modelContext.save()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }
            Button("Add Custom Emulator…") { isPresentingNewProfile = true }
        } header: {
            Text("Custom Emulators")
        } footer: {
            Text("Add a standalone emulator to launch specific systems or games with instead of RetroArch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
