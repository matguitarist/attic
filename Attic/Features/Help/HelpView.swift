import SwiftUI
import SwiftData
import AtticModels
import AtticPersistence
import AtticEmulation

enum HelpPage: Hashable {
    case topic(HelpTopic)
    case system(CanonicalSystemID)
}

/// Which help page is showing, so other windows can open help on a given
/// page (e.g. a system's page from Settings › Emulators).
@Observable
@MainActor
final class HelpNavigator {
    var selection: HelpPage? = .topic(.gettingStarted)
}

/// The Attic Help window (Help › Attic Help): general topics, then one
/// page per supported system, grouped like the library's sidebar.
struct HelpView: View {
    static let windowID = "help"

    @Environment(HelpNavigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator

        NavigationSplitView {
            List(selection: $navigator.selection) {
                Section("Help") {
                    ForEach(HelpTopic.allCases) { topic in
                        Label(topic.title, systemImage: topic.symbolName)
                            .tag(HelpPage.topic(topic))
                    }
                }
                ForEach(SystemCategory.allCases, id: \.self) { category in
                    let systems = SystemTaxonomy.allSystems
                        .filter { $0.category == category }
                        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
                    if !systems.isEmpty {
                        Section(category.title) {
                            ForEach(systems, id: \.canonicalID) { system in
                                Label(system.displayName, systemImage: category.symbolName)
                                    .lineLimit(1)
                                    .tag(HelpPage.system(system.canonicalID))
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            switch navigator.selection {
            case .topic(let topic)?:
                HelpTopicView(topic: topic)
            case .system(let systemID)?:
                SystemHelpView(systemID: systemID)
            case nil:
                ContentUnavailableView("Select a Topic", systemImage: "questionmark.circle")
            }
        }
    }
}

private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        Form {
            ForEach(topic.sections, id: \.heading) { section in
                Section(section.heading) {
                    ForEach(section.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(topic.title)
    }
}

/// One system's page, modeled on RetroBat's wiki: information, emulators,
/// BIOS, controls and notes — with live status from this Mac where it has
/// one (installed or not, BIOS present or missing).
private struct SystemHelpView: View {
    let systemID: CanonicalSystemID

    @Environment(EmulatorSetupCoordinator.self) private var setup
    @Environment(RetroArchSettingsStore.self) private var retroArchStore
    @Environment(EmulationFolderStore.self) private var emulationFolderStore
    @Query private var librarySystems: [GameSystem]
    /// Bumped after BIOS files move, so their status redraws.
    @State private var biosCheck = 0

    private var definition: SystemDefinition? { SystemTaxonomy.definition(for: systemID) }
    private var info: SystemHelpInfo? { SystemHelpContent.info(for: systemID) }
    private var recommendation: SystemEmulatorRecommendation? { EmulatorCatalog.recommendation(for: systemID) }

    var body: some View {
        Form {
            headerSection
            informationSection
            emulatorsSection
            biosSection
            if let controls = info?.controls, !controls.isEmpty {
                paragraphs("Controls", controls)
            }
            if let notes = info?.notes, !notes.isEmpty {
                paragraphs("Notes", notes)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(definition?.displayName ?? systemID.rawValue)
        // PS2 dumps dropped into BIOS/ itself go where PCSX2 looks.
        .task(id: systemID) {
            if !emulationFolderStore.folder.movePS2BIOSIntoPlace().isEmpty { biosCheck += 1 }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: (definition?.category ?? .console).symbolName)
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition?.displayName ?? systemID.rawValue)
                        .font(.title2.bold())
                    if let info {
                        Text(verbatim: SystemFacts.summary(for: systemID) ?? info.manufacturer)
                            .foregroundStyle(.secondary)
                    }
                    if let count = librarySystems.first(where: { $0.systemID == systemID })?.gameCount, count > 0 {
                        Text("\(count) games in your library")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let info {
                    Link(destination: info.wikipediaURL) {
                        Label("Wikipedia", systemImage: "safari")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var informationSection: some View {
        Section("Information") {
            if let definition {
                LabeledContent("ROM Folder") {
                    Text(romFolderNames(definition))
                        .textSelection(.enabled)
                        .monospaced()
                }
            }
            let extensions = fileExtensions
            if !extensions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("File Types")
                    TagList(items: extensions.map { ".\($0)" })
                }
            }
            if let recommendation {
                LabeledContent("Recommended Emulator") {
                    Text(recommendation.prefersStandalone
                        ? recommendation.standalone.first?.name ?? ""
                        : recommendation.recommendedCore?.displayName ?? "")
                }
            }
        }
    }

    @ViewBuilder
    private var emulatorsSection: some View {
        if let recommendation {
            Section {
                let standalone = recommendation.standalone.map { (name: $0.name, summary: $0.summary, kind: String(localized: "Standalone app"), installed: setup.isStandaloneInstalled($0)) }
                let cores = recommendation.cores.map { (name: $0.displayName, summary: $0.summary, kind: String(localized: "RetroArch core"), installed: retroArchStore.core(withIdentifier: $0.coreIdentifier) != nil) }
                let rows = recommendation.prefersStandalone ? standalone + cores : cores + standalone
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(row.name)
                                if index == 0 {
                                    Text(String(localized: "help.badge.recommended", defaultValue: "Recommended"))
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.tint.opacity(0.2), in: .capsule)
                                }
                            }
                            Text("\(row.kind) — \(row.summary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusLabel(row.installed, yes: "Installed", no: "Not installed")
                    }
                }
            } header: {
                Text("Emulators")
            } footer: {
                SettingsLink {
                    Text("Install and choose emulators in Settings…")
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var biosSection: some View {
        let requirements = recommendation?.bios ?? []
        let _ = biosCheck
        Section {
            if requirements.isEmpty {
                Text("No BIOS needed.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(requirements, id: \.fileName) { requirement in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Tag(requirement.fileName)
                            Text([requirement.required ? String(localized: "Required") : String(localized: "Optional"), requirement.note]
                                .compactMap { $0 }
                                .joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !requirement.supportedDumps.isEmpty {
                                Text("Any model works, for example:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TagList(items: requirement.supportedDumps)
                                    .padding(.top, 2)
                            }
                        }
                        Spacer()
                        statusLabel(biosIsPresent(requirement), yes: "Found", no: "Missing", missingIsWarning: requirement.required)
                    }
                }
            }
        } header: {
            Text("BIOS")
        } footer: {
            if !requirements.isEmpty {
                Text("Put BIOS files in \(setup.biosDirectoryPath). Dump them from hardware you own; Attic never downloads them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func paragraphs(_ heading: LocalizedStringKey, _ items: [String]) -> some View {
        Section(heading) {
            ForEach(items, id: \.self) { item in
                Text(item).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusLabel(_ ok: Bool, yes: LocalizedStringKey, no: LocalizedStringKey, missingIsWarning: Bool = false) -> some View {
        Label(ok ? yes : no, systemImage: ok ? "checkmark.circle.fill" : (missingIsWarning ? "exclamationmark.triangle.fill" : "circle"))
            .font(.caption)
            .foregroundStyle(ok ? .green : (missingIsWarning ? .orange : .secondary))
    }

    // MARK: - Data

    private func romFolderNames(_ definition: SystemDefinition) -> String {
        SystemFacts.romFolderNames(definition)
    }

    private var fileExtensions: [String] {
        SystemFacts.fileExtensions(for: systemID, coreInfo: emulationFolderStore.folder.coreInfo)
    }

    private func biosIsPresent(_ requirement: BIOSRequirement) -> Bool {
        requirement.isPresent(in: emulationFolderStore.folder.bios)
    }
}

/// Facts about a system shown both on its help page and in the library's
/// system overview.
enum SystemFacts {
    static func romFolderNames(_ definition: SystemDefinition) -> String {
        definition.allShortNames
            .map { "ROMs/\($0)" }
            .joined(separator: "  ")
    }

    /// Everything the system's emulators accept, read from libretro's core
    /// info files; arcade boards take zipped romsets whatever the core says.
    static func fileExtensions(for systemID: CanonicalSystemID, coreInfo: URL) -> [String] {
        guard let recommendation = EmulatorCatalog.recommendation(for: systemID) else { return [] }
        if SystemTaxonomy.definition(for: systemID)?.category == .arcade, !recommendation.cores.isEmpty { return ["zip", "7z"] }
        var seen: [String] = []
        for core in recommendation.cores {
            for ext in RetroArchCoreInfo.supportedExtensions(ofCore: core.coreIdentifier, infoDirectory: coreInfo)
            where !seen.contains(ext.lowercased()) {
                seen.append(ext.lowercased())
            }
        }
        if seen.isEmpty, systemID == .triforce { return ["iso", "gcz", "rvz", "ciso"] }
        if seen.isEmpty, systemID == .xbox { return ["iso"] }
        return seen
    }

    /// "Any model works, for example scph39001.bin, …" for a folder
    /// requirement.
    static func supportedDumps(_ requirement: BIOSRequirement) -> String? {
        guard !requirement.supportedDumps.isEmpty else { return nil }
        return String(localized: "Any model works, for example \(requirement.supportedDumps.formatted(.list(type: .and)))")
    }

    /// "Nintendo · 1990 · Console".
    static func summary(for systemID: CanonicalSystemID) -> String? {
        guard let info = SystemHelpContent.info(for: systemID) else { return nil }
        let category = (SystemTaxonomy.definition(for: systemID)?.category ?? .console).title
        return "\(info.manufacturer) · \(info.year.formatted(.number.grouping(.never))) · \(category)"
    }
}
