import SwiftUI
import AtticModels

/// A controller button or keyboard key, at the size of the text around it.
struct ButtonGlyphView: View {
    let glyph: ButtonGlyph

    nonisolated init(_ glyph: ButtonGlyph) {
        self.glyph = glyph
    }

    var body: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
        case .key(let label):
            Text(verbatim: label)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .padding(.horizontal, 6)
                .frame(minWidth: 24, minHeight: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(lineWidth: 1.5)
                }
        }
    }
}

extension ControllerFamily {
    var title: String {
        switch self {
        case .xbox: String(localized: "Xbox")
        case .playStation: String(localized: "PlayStation")
        case .nintendo: String(localized: "Nintendo Switch")
        case .eightBitDo: String(localized: "8BitDo")
        case .stadia: String(localized: "Stadia")
        case .keyboard: String(localized: "Keyboard")
        }
    }
}

extension Label where Title == Text, Icon == ButtonGlyphView {
    /// A hint: what a button does, with the button.
    init(_ title: LocalizedStringKey, glyph: ButtonGlyph) {
        self.init { Text(title) } icon: { ButtonGlyphView(glyph) }
    }
}
