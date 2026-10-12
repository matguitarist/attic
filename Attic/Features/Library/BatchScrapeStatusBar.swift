import SwiftUI

/// Shown only while a scrape is running or just finished — a bulk scrape
/// with its progress, or a single game's scrape from a menu with what it
/// filled in — and hidden the rest of the time so it doesn't take up
/// permanent space in the layout.
struct BatchScrapeStatusBar: View {
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator

    var body: some View {
        switch scrapeCoordinator.batchState {
        case .idle:
            if let activity = scrapeCoordinator.activity {
                activityRow(activity)
            }

        case .running(let completed, let total):
            HStack(spacing: 10) {
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                    .frame(maxWidth: 240)
                Text("Scraping \(completed + 1) of \(total)…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { scrapeCoordinator.cancelBatch() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

        case .finished(let scraped, let alreadyPresent, let failed):
            HStack(spacing: 10) {
                Image(systemName: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(failed == 0 ? .green : .orange)
                Text(summary(scraped: scraped, alreadyPresent: alreadyPresent, failed: failed))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") { scrapeCoordinator.cancelBatch() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func activityRow(_ activity: ScrapeCoordinator.Activity) -> some View {
        HStack(spacing: 10) {
            switch activity {
            case .scraping(let title, let source):
                ProgressView().controlSize(.small)
                Text("Scraping “\(title)” from \(source)…")
            case .updated(let title, let fields):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Updated “\(title)”: \(fields.formatted(.list(type: .and)))")
            case .nothingNew(let title):
                Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                Text("Nothing new for “\(title)”: it already has everything found. Use Scrape Info › Replace Existing Info to overwrite it.")
            case .failed(let title, let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Couldn't scrape “\(title)”: \(message)")
            }
            Spacer()
            if case .scraping = activity {
                EmptyView()
            } else {
                Button("Dismiss") { scrapeCoordinator.dismissActivity() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func summary(scraped: Int, alreadyPresent: Int, failed: Int) -> String {
        var parts = [String(localized: "\(scraped) scraped")]
        if failed > 0 { parts.append(String(localized: "\(failed) failed")) }
        if alreadyPresent > 0 { parts.append(String(localized: "\(alreadyPresent) already had info")) }
        return parts.joined(separator: ", ")
    }
}
