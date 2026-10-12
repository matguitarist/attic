import SwiftUI
import AtticModels

/// Create/edit form for one `EmulatorProfile`, used as a sheet from
/// `EmulatorProfilesSettingsView`.
struct EmulatorProfileEditorView: View {
    let title: LocalizedStringKey
    @State var name: String
    @State var executablePath: String
    @State var argumentTemplate: String
    @State var assignedSystemIDs: Set<CanonicalSystemID>

    let onSave: (String, String, String, Set<CanonicalSystemID>) -> Void
    let onCancel: () -> Void

    @State private var isChoosingExecutable = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                HStack {
                    TextField("Executable Path", text: $executablePath)
                    Button("Choose…") { isChoosingExecutable = true }
                }
                TextField("Arguments", text: $argumentTemplate)
                Text("Placeholders: {romPath}, {romDir}, {romName}, {romNameNoExt}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Assigned Systems") {
                ForEach(SystemTaxonomy.allSystems, id: \.canonicalID) { system in
                    Toggle(system.displayName, isOn: bindingFor(system.canonicalID))
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .fileImporter(isPresented: $isChoosingExecutable, allowedContentTypes: [.application, .unixExecutable]) { result in
            if case .success(let url) = result {
                executablePath = url.path
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(name, executablePath, argumentTemplate, assignedSystemIDs)
                }
                .disabled(name.isEmpty || executablePath.isEmpty)
            }
        }
    }

    private func bindingFor(_ id: CanonicalSystemID) -> Binding<Bool> {
        Binding(
            get: { assignedSystemIDs.contains(id) },
            set: { isOn in
                if isOn { assignedSystemIDs.insert(id) } else { assignedSystemIDs.remove(id) }
            }
        )
    }
}
