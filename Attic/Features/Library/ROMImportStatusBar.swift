import SwiftUI

/// Shown while dropped games are being added, so a big folder doesn't
/// look like Attic froze.
struct ROMImportStatusBar: View {
    let importer: ROMImportCoordinator

    var body: some View {
        if let progress = importer.progress {
            HStack(spacing: 10) {
                switch progress {
                case .looking:
                    ProgressView().controlSize(.small)
                    Text("Looking for games…")
                case .adding(let done, let total, let name):
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                        .frame(maxWidth: 240)
                    Text("Adding \(done + 1) of \(total): \(name)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
