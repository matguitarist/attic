import SwiftUI

/// Shown only while a bulk scrape is running or just finished — hidden the
/// rest of the time so it doesn't take up permanent space in the layout.
struct BatchScrapeStatusBar: View {
    @Environment(ScrapeCoordinator.self) private var scrapeCoordinator

    var body: some View {
        switch scrapeCoordinator.batchState {
        case .idle:
            EmptyView()

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

    private func summary(scraped: Int, alreadyPresent: Int, failed: Int) -> String {
        var parts = [String(localized: "\(scraped) scraped")]
        if failed > 0 { parts.append(String(localized: "\(failed) failed")) }
        if alreadyPresent > 0 { parts.append(String(localized: "\(alreadyPresent) already had info")) }
        return parts.joined(separator: ", ")
    }
}
