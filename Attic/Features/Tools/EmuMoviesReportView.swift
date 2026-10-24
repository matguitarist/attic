import SwiftUI
import AtticModels
import AtticLibraryScanning
import AtticEmulation

/// What EmuMovies has for the library, before anything is downloaded:
/// the kinds of media to get, the systems to get them for, and which of
/// a system's packs to use.
struct EmuMoviesReportView: View {
    let plan: EmuMoviesPlan
    let onGet: (EmuMoviesChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<CanonicalSystemID>
    @State private var kinds: Set<MediaKind>
    @AppStorage("emuMoviesManuals") private var manuals = true
    @AppStorage("emuMoviesVideos") private var videos = true
    /// Off at first: a system's game videos take a few GB.
    @AppStorage("emuMoviesSnaps") private var snaps = false
    @AppStorage("emuMoviesReplacing") private var replacing = EmuMoviesChoice.Replacing.keep
    /// Packs picked instead of the ones Attic would use.
    @State private var packs: [CanonicalSystemID: [MediaKind: EmuMovies.Pack]] = [:]

    init(plan: EmuMoviesPlan, onGet: @escaping (EmuMoviesChoice) -> Void) {
        self.plan = plan
        self.onGet = onGet
        _chosen = State(initialValue: [])
        let kinds = UserDefaults.standard.stringArray(forKey: Self.kindsKey)?
            .compactMap { MediaKind(rawValue: $0) ?? MediaKind.renamedKinds[$0] }
        _kinds = State(initialValue: Set(kinds ?? [.covers, .logos]))
    }

    /// What was picked last time, picked again.
    private static let systemsKey = "emuMoviesSystems"
    private static let kindsKey = "emuMoviesKinds"

    private func remember() {
        UserDefaults.standard.set(chosen.map(\.rawValue).sorted(), forKey: Self.systemsKey)
        UserDefaults.standard.set(kinds.map(\.rawValue).sorted(), forKey: Self.kindsKey)
    }

    private func packs(of system: EmuMoviesPlan.System) -> [MediaKind: EmuMovies.Pack] {
        system.chosen.merging(packs[system.id] ?? [:]) { _, picked in picked }
    }

    private var choice: EmuMoviesChoice {
        EmuMoviesChoice(systems: chosen, kinds: kinds, manuals: manuals, videos: videos, snaps: snaps, replacing: replacing,
                        packs: Dictionary(uniqueKeysWithValues: plan.systems.map { ($0.id, packs(of: $0)) }))
    }

    private var isLooking: Bool {
        chosen.contains { plan.lookups[$0] == .waiting || plan.lookups[$0] == .looking }
    }

    private func choose(_ id: CanonicalSystemID, _ on: Bool) {
        if on {
            chosen.insert(id)
            plan.lookUp(id)
        } else {
            chosen.remove(id)
            plan.forget(id)
        }
    }

    /// What a system would get, and the download it takes.
    private func work(_ system: EmuMoviesPlan.System) -> (parts: [String], bytes: Int64) {
        var parts: [String] = []
        var bytes: Int64 = 0
        guard plan.lookups[system.id] == .done else { return (parts, bytes) }
        for kind in EmuMoviesPlan.kinds where kinds.contains(kind) {
            guard let pack = packs(of: system)[kind] else { continue }
            let games = replacing == .all ? system.games : system.missing[kind] ?? 0
            let sharper = replacing == .lowQuality ? system.lowQuality[kind]?.count ?? 0 : 0
            guard games + sharper > 0 else { continue }
            parts.append(sharper > 0 ? "\(kind.title.lowercased()) (\(games) + \(String(localized: "\(sharper) to improve")))"
                                     : "\(kind.title.lowercased()) (\(games))")
            bytes += pack.size
        }
        if manuals {
            let count = replacing == .all ? system.manuals.count : system.missingManuals
            if count > 0 {
                parts.append(String(localized: "\(count) manuals"))
                bytes += system.manuals.values.reduce(0) { $0 + $1.size } * Int64(count) / Int64(max(system.manuals.count, 1))
            }
        }
        if snaps {
            let needing = system.snaps.filter { replacing == .all || $0.value.missing || (replacing == .lowQuality && $0.value.lowQuality) }
            if !needing.isEmpty {
                let sharper = replacing == .lowQuality ? needing.values.filter(\.lowQuality).count : 0
                parts.append(sharper > 0 ? String(localized: "\(needing.count - sharper) game videos + \(sharper) to improve")
                                         : String(localized: "\(needing.count) game videos"))
                bytes += needing.values.reduce(0) { $0 + $1.file.size }
            }
        }
        if videos, let video = system.video,
           replacing == .all || !system.hasVideo || (replacing == .lowQuality && system.videoIsLowQuality) {
            parts.append(system.hasVideo && replacing == .lowQuality ? String(localized: "sharper system video") : String(localized: "system video"))
            bytes += video.size
        }
        return (parts, bytes)
    }

    private var totalBytes: Int64 {
        plan.systems.filter { chosen.contains($0.id) }.reduce(0) { $0 + work($1).bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Get Media from EmuMovies")
                    .font(.title2.bold())
                Text("Artwork comes in one pack per system and kind: Attic downloads it, keeps the pictures of your games and deletes the rest.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Form {
                Section("Media") {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(EmuMoviesPlan.kinds, id: \.self) { kind in
                            Toggle(kind.title, isOn: Binding(
                                get: { kinds.contains(kind) },
                                set: { if $0 { kinds.insert(kind) } else { kinds.remove(kind) } }
                            ))
                        }
                        Toggle("Manuals", isOn: $manuals)
                        Toggle("Game Videos", isOn: $snaps)
                        Toggle("System Videos", isOn: $videos)
                    }
                    .toggleStyle(.checkbox)
                    Picker(selection: $replacing) {
                        Text("Keep it: only games missing something get it").tag(EmuMoviesChoice.Replacing.keep)
                        Text("Replace small pictures and videos when EmuMovies' are sharper").tag(EmuMoviesChoice.Replacing.lowQuality)
                        Text("Replace it all").tag(EmuMoviesChoice.Replacing.all)
                    } label: {
                        Text("Media your games already have")
                        Text("Small means fan art below 1920 × 1080, covers and boxes under 1000 pixels, logos under 600 and videos under 480 lines. Each is compared with EmuMovies' once downloaded and kept unless that one is sharper. Files replaced go to the Trash.")
                    }
                    .pickerStyle(.radioGroup)
                }

                Section {
                    ForEach(plan.systems) { system in
                        row(system)
                    }
                } header: {
                    HStack {
                        Text("Systems")
                        Spacer()
                        Button("All") { for system in plan.systems { choose(system.id, true) } }
                        Button("None") { for id in chosen { choose(id, false) } }
                    }
                    .buttonStyle(.link)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Games are matched by file name, then by title. 2D and 3D boxes, cartridges and logos are scaled to 1400 pixels at most, fan art to 1920, and saved as HEIC.")
                        if plan.unar == nil {
                            Text("Some packs are split in parts, which need unar to open: install it with Homebrew (brew install unar), then look again to use them.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack(alignment: .firstTextBaseline) {
                Text(chosen.isEmpty ? String(localized: "Choose the systems to get media for.")
                     : isLooking ? String(localized: "Looking on EmuMovies…")
                     : String(localized: "About \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) to download"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    plan.stop()
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                Button("Get Media") {
                    remember()
                    dismiss()
                    onGet(choice)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(totalBytes == 0 || isLooking)
            }
            .padding(20)
        }
        .frame(width: 720, height: 680)
        .onAppear {
            let last = Set(UserDefaults.standard.stringArray(forKey: Self.systemsKey) ?? [])
            for system in plan.systems where last.contains(system.id.rawValue) { choose(system.id, true) }
        }
        .onDisappear { plan.stop() }
    }

    @ViewBuilder
    private func status(_ system: EmuMoviesPlan.System, _ work: (parts: [String], bytes: Int64)) -> some View {
        switch plan.lookups[system.id] {
        case .waiting?:
            Text("Waiting…")
        case .looking?:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Looking on EmuMovies…")
            }
        case .failed(let message)?:
            Text(message).foregroundStyle(.orange)
        case .done?:
            Text(work.parts.isEmpty ? String(localized: "Nothing to add") : work.parts.joined(separator: ", "))
        case nil:
            Text("Tick it to see what EmuMovies has.")
        }
    }

    private func row(_ system: EmuMoviesPlan.System) -> some View {
        let work = work(system)
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { chosen.contains(system.id) }, set: { choose(system.id, $0) })) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(system.name)
                        status(system, work)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(localized: "\(system.games) games"))
                            .foregroundStyle(.secondary)
                        if work.bytes > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: work.bytes, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .monospacedDigit()
                }
            }
            .toggleStyle(.checkbox)

            let usable = system.packs.filter { plan.unar != nil || !$0.isSplit }
            let choices = EmuMoviesPlan.kinds.filter { kind in kinds.contains(kind) && usable.filter { $0.kind == kind }.count > 1 }
            if !choices.isEmpty {
                DisclosureGroup("Packs") {
                    ForEach(choices, id: \.self) { kind in
                        Picker(kind.title, selection: Binding(
                            get: { packs(of: system)[kind] },
                            set: { packs[system.id, default: [:]][kind] = $0 }
                        )) {
                            ForEach(usable.filter { $0.kind == kind }) { pack in
                                Text(verbatim: "\(pack.name) — \(ByteCountFormatter.string(fromByteCount: pack.size, countStyle: .file))")
                                    .tag(Optional(pack))
                            }
                        }
                    }
                }
                .font(.caption)
                .padding(.leading, 22)
            }
        }
    }
}
