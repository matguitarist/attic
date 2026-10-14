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

    private var leftoverPaths: [String] {
        plan.leftovers.map { $0.path.replacingOccurrences(of: report.folder.path + "/", with: "") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

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
                            DisclosureGroup {
                                chips(rebuild.parts)
                                let replaced = rebuild.dropped.filter { name in rebuild.parts.contains { $0.name == name } }
                                let left = rebuild.dropped.filter { !replaced.contains($0) }
                                if !replaced.isEmpty {
                                    note("Replaced, from another version: \(replaced.formatted(.list(type: .and)))")
                                }
                                if !left.isEmpty {
                                    note("Left out, not part of this set: \(left.formatted(.list(type: .and)))")
                                }
                            } label: {
                                LabeledContent {
                                    Text(sources(of: rebuild))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                } label: {
                                    Text(rebuild.title)
                                    Text(verbatim: rebuild.zip.lastPathComponent).monospaced()
                                }
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

                if !plan.incomplete.isEmpty {
                    Section {
                        ForEach(plan.incomplete) { set in
                            DisclosureGroup {
                                missing(set.missing)
                                if !set.found.isEmpty {
                                    note("\(set.found.count) other chips were found.")
                                }
                            } label: {
                                LabeledContent {
                                    Text("\(set.missing.count) missing")
                                        .foregroundStyle(.orange)
                                } label: {
                                    Text(set.title)
                                    Text(verbatim: set.name + ".zip").monospaced()
                                }
                            }
                        }
                    } header: {
                        Text("Can't Be Made Whole")
                    } footer: {
                        Text("No file here has these chips. They're left as they are, and so are the loose files they use.")
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
                            // Sorted by path, so each folder's files sit together.
                            ForEach(leftoverPaths, id: \.self) { path in
                                Text(verbatim: path)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .disabled(plan.rebuilds.isEmpty && (!trashingLeftovers || plan.leftovers.isEmpty))
            }
            .padding(20)
        }
        .frame(width: 600, height: 560)
    }

    /// Each chip, its CRC32, and where it's taken from.
    private func chips(_ parts: [SetRebuild.Part]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                Text("File")
                Text(verbatim: "CRC32")
                Text("From")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(parts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, id: \.self) { part in
                GridRow {
                    Text(verbatim: part.name)
                    Text(verbatim: String(format: "%08x", part.crc)).foregroundStyle(.green)
                    Text(verbatim: part.entry == nil
                         ? part.source.path.replacingOccurrences(of: report.folder.path + "/", with: "")
                         : part.source.lastPathComponent)
                        .foregroundStyle(part.entry == nil ? Color.accentColor : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }

    private func missing(_ files: [SetProblems.File]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            GridRow {
                Text("File")
                Text(verbatim: "CRC32")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(files, id: \.self) { file in
                GridRow {
                    Text(verbatim: file.name)
                    Text(verbatim: file.expected).foregroundStyle(.orange)
                }
            }
        }
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
