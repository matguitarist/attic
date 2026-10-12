import SwiftUI
import AtticModels

/// Asks which system dropped files are for, when their type fits several.
struct ROMImportSheet: View {
    let question: ROMImportCoordinator.Question
    let answer: (CanonicalSystemID?) -> Void
    @State private var choice: CanonicalSystemID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Which System Are These For?")
                .font(.headline)
            Text(fileList)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Picker("System", selection: $choice) {
                ForEach(question.choices, id: \.self) { system in
                    Text(SystemTaxonomy.definition(for: system)?.displayName ?? system.rawValue).tag(Optional(system))
                }
            }
            .pickerStyle(.menu)
            HStack {
                Spacer()
                Button("Skip") { answer(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { answer(choice) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(choice == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { choice = question.choices.first }
    }

    private var fileList: String {
        let names = question.files.map(\.lastPathComponent)
        let shown = names.prefix(3).joined(separator: "\n")
        return names.count > 3 ? shown + "\n" + String(localized: "and \(names.count - 3) more") : shown
    }
}
