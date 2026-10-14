import SwiftUI

/// What importing from another front-end would bring, before it's done.
struct MediaImportReportView: View {
    let plan: MediaImportPlan
    let onImport: (_ replacing: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var replacing = false

    private var total: MediaImportPlan.Counts {
        plan.systems.reduce(into: MediaImportPlan.Counts()) { total, system in
            let counts = counts(of: system)
            total.covers += counts.covers
            total.screenshots += counts.screenshots
            total.videos += counts.videos
            total.manuals += counts.manuals
            total.descriptions += counts.descriptions
        }
    }

    private func counts(of system: MediaImportPlan.System) -> MediaImportPlan.Counts {
        replacing ? system.available : system.missing
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import from Another Front-End")
                    .font(.title2.bold())
                Text(verbatim: plan.folder.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Form {
                Section {
                    ForEach(plan.systems) { system in
                        LabeledContent {
                            Text(String(localized: "\(system.matched) games"))
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(system.name)
                            Text(summary(counts(of: system)))
                        }
                    }
                } header: {
                    Text("Your games it lists")
                } footer: {
                    Text("Games are matched by file name. Covers come from each game's thumbnail (the box), screenshots from its image; covers are saved as HEIC when that's smaller.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: $replacing) {
                        Text("Replace what games already have")
                        Text("Their media and info are replaced by the other front-end's, where it has some. The files replaced go to the Trash.")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Text(summary(total))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    dismiss()
                    onImport(replacing)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(total.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 620, height: 560)
    }

    private func summary(_ counts: MediaImportPlan.Counts) -> String {
        guard !counts.isEmpty else { return String(localized: "Nothing to add") }
        var parts: [String] = []
        if counts.covers > 0 { parts.append(String(localized: "\(counts.covers) covers")) }
        if counts.screenshots > 0 { parts.append(String(localized: "\(counts.screenshots) screenshots")) }
        if counts.videos > 0 { parts.append(String(localized: "\(counts.videos) videos")) }
        if counts.manuals > 0 { parts.append(String(localized: "\(counts.manuals) manuals")) }
        if counts.descriptions > 0 { parts.append(String(localized: "\(counts.descriptions) descriptions")) }
        return parts.formatted(.list(type: .and))
    }
}
