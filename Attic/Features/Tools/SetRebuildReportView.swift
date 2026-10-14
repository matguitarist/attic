import SwiftUI
import AtticEmulation

/// What rebuilding a system's sets would do, before it's done: each set
/// and where its chips come from, and the loose files left over.
struct SetRebuildReportView: View {
    let report: SetRebuildReport
    let onRebuild: (_ trashingLeftovers: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var trashingLeftovers = true
    @State private var showsLeftovers = false

    private var plan: RebuildPlan { report.plan }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rebuild Sets").font(.title2.bold())
                Text(verbatim: report.folder.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Form {
                if !plan.rebuilds.isEmpty {
                    Section {
                        ForEach(plan.rebuilds) { rebuild in
                            LabeledContent {
                                Text(sources(of: rebuild))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            } label: {
                                Text(rebuild.title)
                                Text(verbatim: rebuild.zip.lastPathComponent).monospaced()
                            }
                        }
                    } header: {
                        Text("Sets")
                    } footer: {
                        Text("Each zip is written with exactly the chips \(plan.dat ?? "the DAT") lists, then checked; the zip it replaces goes to the Trash.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !plan.leftovers.isEmpty {
                    Section {
                        Toggle(isOn: $trashingLeftovers) {
                            Text("Move the leftover loose files to the Trash")
                            Text("\(plan.leftovers.count) files, \(ByteCountFormatter.string(fromByteCount: plan.leftoverBytes, countStyle: .file)): their chips are in a zip, or none of the sets here uses them.")
                        }
                        DisclosureGroup("Files", isExpanded: $showsLeftovers) {
                            ForEach(plan.leftovers, id: \.self) { file in
                                Text(verbatim: file.path.replacingOccurrences(of: report.folder.path + "/", with: ""))
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    } header: {
                        Text("Loose Files")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(plan.rebuilds.isEmpty ? String(localized: "Move to Trash") : String(localized: "Rebuild")) {
                    dismiss()
                    onRebuild(trashingLeftovers)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.rebuilds.isEmpty && !trashingLeftovers)
            }
            .padding(20)
        }
        .frame(width: 600, height: 560)
    }

    /// "33 chips: 5 from loose files, 28 from jojoba.zip".
    private func sources(of rebuild: SetRebuild) -> String {
        let zips = Dictionary(grouping: rebuild.parts.filter { $0.entry != nil }, by: \.source.lastPathComponent)
            .sorted { $0.key < $1.key }
            .map { String(localized: "\($0.value.count) from \($0.key)") }
        let loose = rebuild.fromLooseFiles > 0 ? [String(localized: "\(rebuild.fromLooseFiles) from loose files")] : []
        return String(localized: "\(rebuild.parts.count) chips: \((loose + zips).formatted(.list(type: .and)))")
    }
}
