import SwiftUI
import AppKit

/// Attic's colors and small shared pieces, so the library, its panels and
/// sheets look alike, in light and dark.
extension Color {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// Behind the covers: a soft grey in light mode rather than white,
    /// which glared beside the panels.
    static let contentBackground = dynamic(light: NSColor(white: 0.925, alpha: 1), dark: .windowBackgroundColor)

    /// A cover's card, before its art loads or when it has none.
    static let card = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.07))

    /// Secondary text that stays readable on light backgrounds, where the
    /// system's grey is faint.
    static let secondaryText = dynamic(light: NSColor(white: 0, alpha: 0.68), dark: NSColor(white: 1, alpha: 0.62))
}

/// A number with its label, as a small tile: "58 · Games".
struct StatTile: View {
    let value: String
    let label: LocalizedStringKey
    var systemImage: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.callout).foregroundStyle(tint)
                }
                Text(verbatim: value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A count or state as a small tinted capsule: "58 verified".
struct StatusTag: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage) }
            Text(verbatim: text).monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(tint.opacity(0.14), in: .capsule)
        .fixedSize()
    }
}
