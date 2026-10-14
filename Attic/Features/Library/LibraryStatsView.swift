import SwiftUI
import SwiftData
import Charts
import AtticPersistence

/// The library in numbers: how much there is, what gets played, and how
/// much room each system takes.
struct LibraryStatsView: View {
    static let windowID = "library-statistics"

    @Query private var games: [Game]
    @Query(filter: #Predicate<PlaySession> { $0.endedAt != nil }) private var sessions: [PlaySession]
    /// Each system's files on disk, read in the background.
    @State private var bytesBySystem: [String: Int64] = [:]

    private struct SystemRow: Identifiable {
        let id: String
        let name: String
        var games = 0
        var playtime: Double = 0
    }

    private struct Month: Identifiable {
        let id: Date
        var hours: Double
    }

    var body: some View {
        let systems = systemRows
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                totals
                playtimeChart
                mostPlayed
                systemsTable(systems)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: games.count) { await measureDisk() }
    }

    // MARK: - Totals

    private var totals: some View {
        let playtime = games.reduce(0) { $0 + $1.totalPlaytimeSeconds }
        let verified = games.filter { $0.datVerdict == "verified" }.count
        let checked = games.filter { $0.datVerdict != nil }.count
        let addedLately = games.filter { ($0.dateAdded ?? .distantPast) > Calendar.current.date(byAdding: .day, value: -30, to: .now)! }.count
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            tile(String(localized: "Games"), value: games.count.formatted())
            tile(String(localized: "Systems"), value: Set(games.map(\.systemCanonicalID)).count.formatted())
            tile(String(localized: "Favorites"), value: games.filter(\.favorite).count.formatted())
            tile(String(localized: "Played"), value: games.filter { $0.playCount > 0 }.count.formatted())
            tile(String(localized: "Play Time"), value: Self.duration(playtime))
            tile(String(localized: "Added, Last 30 Days"), value: addedLately.formatted())
            if checked > 0 {
                tile(String(localized: "Verified Dumps"), value: "\(Int((Double(verified) / Double(checked) * 100).rounded()))%")
            }
            let bytes = bytesBySystem.values.reduce(0, +)
            if bytes > 0 {
                tile(String(localized: "On Disk"), value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            }
        }
    }

    private func tile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Play time

    private var months: [Month] {
        let calendar = Calendar.current
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now))!
        var months = (0..<12).reversed().map { Month(id: calendar.date(byAdding: .month, value: -$0, to: thisMonth)!, hours: 0) }
        for session in sessions {
            guard let end = session.endedAt else { continue }
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: session.startedAt))!
            if let index = months.firstIndex(where: { $0.id == month }) {
                months[index].hours += max(0, end.timeIntervalSince(session.startedAt)) / 3600
            }
        }
        return months
    }

    @ViewBuilder
    private var playtimeChart: some View {
        let months = months
        if months.contains(where: { $0.hours > 0 }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Play Time, Last 12 Months").font(.headline)
                Chart(months) { month in
                    BarMark(x: .value("Month", month.id, unit: .month), y: .value("Hours", month.hours))
                        .foregroundStyle(.tint)
                }
                .chartYAxisLabel(String(localized: "Hours"))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Most played

    @ViewBuilder
    private var mostPlayed: some View {
        let top = games.filter { $0.totalPlaytimeSeconds > 0 }
            .sorted { $0.totalPlaytimeSeconds > $1.totalPlaytimeSeconds }
            .prefix(10)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Most Played").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(Array(top.enumerated()), id: \.element.persistentModelID) { index, game in
                        GridRow {
                            Text(verbatim: "\(index + 1)").foregroundStyle(.secondary).monospacedDigit()
                            Text(game.title).lineLimit(1)
                            Text(game.system?.displayName ?? game.systemCanonicalID).foregroundStyle(.secondary).lineLimit(1)
                            Text(Self.duration(game.totalPlaytimeSeconds)).monospacedDigit()
                                .gridColumnAlignment(.trailing)
                            Text(String(localized: "\(game.playCount) sessions")).foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Systems

    private var systemRows: [SystemRow] {
        var rows: [String: SystemRow] = [:]
        for game in games {
            var row = rows[game.systemCanonicalID]
                ?? SystemRow(id: game.systemCanonicalID, name: game.system?.displayName ?? game.systemCanonicalID)
            row.games += 1
            row.playtime += game.totalPlaytimeSeconds
            rows[game.systemCanonicalID] = row
        }
        return rows.values.sorted { $0.games != $1.games ? $0.games > $1.games : $0.name < $1.name }
    }

    private func systemsTable(_ systems: [SystemRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Systems").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("System")
                    Text("Games").gridColumnAlignment(.trailing)
                    Text("Play Time").gridColumnAlignment(.trailing)
                    Text("On Disk").gridColumnAlignment(.trailing)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Divider()
                ForEach(systems) { system in
                    GridRow {
                        Text(system.name).lineLimit(1)
                        Text(system.games.formatted()).monospacedDigit()
                        Text(system.playtime > 0 ? Self.duration(system.playtime) : "—").monospacedDigit()
                        Text(bytesBySystem[system.id].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "…")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Adds up each system's game files (a disc's tracks included).
    private func measureDisk() async {
        let files = games.map { ($0.systemCanonicalID, $0.romAbsoluteURL) }
        bytesBySystem = await Task.detached(priority: .utility) {
            var bytes: [String: Int64] = [:]
            for (system, url) in files {
                bytes[system, default: 0] += Self.size(of: url)
            }
            return bytes
        }.value
    }

    nonisolated static func size(of url: URL) -> Int64 {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard ["cue", "gdi", "m3u"].contains(url.pathExtension.lowercased()),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return size }
        // The files a cue sheet, GDI or playlist names.
        let folder = url.deletingLastPathComponent()
        let names = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let line = line.trimmingCharacters(in: .whitespaces)
            if let quoted = line.firstMatch(of: #/"([^"]+)"/#) { return String(quoted.output.1) }
            if url.pathExtension.lowercased() == "m3u", !line.isEmpty, !line.hasPrefix("#") { return line }
            return nil
        }
        return Set(names).reduce(size) { total, name in
            total + Int64((try? folder.appending(path: name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    static func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }
}
