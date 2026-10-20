import AppKit
import SwiftUI
import AtticEmulation

extension LogLevel {
    /// Dim debug, plain info, orange warnings, red errors.
    var color: Color {
        switch self {
        case .debug: .secondary
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }

    var symbol: String {
        switch self {
        case .debug: "ladybug"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .warning: "Warnings"
        case .error: "Errors"
        }
    }
}

/// Window › Log: what Attic did and what emulators printed, with colored
/// levels, filters and search. Follows new messages while a game runs.
struct LogView: View {
    static let windowID = "log"

    @State private var log = AppLog.shared
    @State private var levels: Set<LogLevel> = [.info, .warning, .error]
    @State private var sourceFilter: String?
    @State private var searchText = ""
    @State private var followLive = true

    var body: some View {
        let shown = filteredEntries
        VStack(spacing: 0) {
            header
            Divider()
            entryList(shown)
        }
        .navigationTitle("Log")
        .navigationSubtitle(AppLog.fileURL.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search log")
        .toolbar { toolbar(shown) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(LogLevel.allCases.reversed(), id: \.self) { level in
                levelChip(level, count: log.entries.lazy.filter { $0.level == level }.count)
            }
            Divider().frame(height: 18).padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sources, id: \.self) { source in
                        sourceChip(source)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var sources: [String] {
        var seen = Set<String>()
        return log.entries.compactMap { seen.insert($0.source).inserted ? $0.source : nil }
    }

    private func levelChip(_ level: LogLevel, count: Int) -> some View {
        let isOn = levels.contains(level)
        return Button {
            if isOn { levels.remove(level) } else { levels.insert(level) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: level.symbol)
                Text(level.title)
                Text(count, format: .number).monospacedDigit()
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isOn ? level.color.opacity(0.2) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(level.color.opacity(isOn ? 0.6 : 0.25)))
            .foregroundStyle(isOn ? level.color : .secondary)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Hide these messages" : "Show these messages")
    }

    private func sourceChip(_ source: String) -> some View {
        let isOn = sourceFilter == source
        return Button {
            sourceFilter = isOn ? nil : source
        } label: {
            Text(verbatim: source)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Self.color(forSource: source).opacity(isOn ? 0.3 : 0.1), in: Capsule())
                .foregroundStyle(Self.color(forSource: source))
        }
        .buttonStyle(.plain)
        .help(isOn ? "Show messages from everything" : "Show only messages from \(source)")
    }

    static func color(forSource source: String) -> Color {
        switch source {
        case "Attic": .accentColor
        case "RetroArch": .teal
        default: .indigo
        }
    }

    // MARK: Entries

    private var filteredEntries: [AppLog.Entry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return log.entries.filter { entry in
            levels.contains(entry.level)
                && (sourceFilter == nil || entry.source == sourceFilter)
                && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query))
        }
    }

    private func entryList(_ entries: [AppLog.Entry]) -> some View {
        ScrollViewReader { proxy in
            List(entries) { entry in
                LogRow(entry: entry, onSourceTap: { sourceFilter = $0 })
                    .listRowBackground(entry.isProblem ? entry.level.color.opacity(0.08) : Color.clear)
                    .id(entry.id)
            }
            .listStyle(.plain)
            .overlay {
                if entries.isEmpty {
                    if log.entries.isEmpty {
                        ContentUnavailableView(
                            "Nothing Logged Yet",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Play a game: what Attic does and what the emulator says while it starts and runs appear here.")
                        )
                    } else {
                        ContentUnavailableView("No Matching Messages", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .onChange(of: entries.last?.id) { _, last in
                if followLive, let last { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onAppear {
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ shown: [AppLog.Entry]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $followLive) {
                Label("Follow Live", systemImage: "dot.radiowaves.left.and.right")
            }
            .help("Scroll to new messages as they arrive")

            Button {
                log.clear()
            } label: {
                Label("Clear", systemImage: "clear")
            }
            .keyboardShortcut("k")
            .help("Clear the window (⌘K). The log file keeps everything.")
            .disabled(log.entries.isEmpty)

            Menu {
                Button("Copy Shown Messages") { copy(log.text(of: shown)) }
                    .disabled(shown.isEmpty)
                Button("Copy Log File") {
                    if let text = try? String(contentsOf: AppLog.fileURL, encoding: .utf8) { copy(text) }
                }
                Divider()
                Button("Show Log File in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppLog.fileURL]) }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Copy the log, or find its file to attach to a bug report")
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct LogRow: View {
    let entry: AppLog.Entry
    let onSourceTap: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .foregroundStyle(.tertiary)
            Text(verbatim: entry.level.code)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(entry.level == .info ? Color.secondary : entry.level.color)
                .frame(width: 44, alignment: .leading)
            Button(entry.source) { onSourceTap(entry.source) }
                .buttonStyle(.plain)
                .foregroundStyle(LogView.color(forSource: entry.source))
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
                .help("Show only \(entry.source)")
            Text(verbatim: entry.message)
                .foregroundStyle(entry.level.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.repeats > 1 {
                Text(verbatim: "×\(entry.repeats)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
                    .help("Repeated \(entry.repeats) times in a row")
            }
        }
        .font(.system(.callout, design: .monospaced))
        .padding(.vertical, 1)
    }
}
