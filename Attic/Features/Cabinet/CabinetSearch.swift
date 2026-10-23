import SwiftUI
import AtticModels

/// The on-screen keyboard X opens: letters, digits, space, delete, clear
/// and done, picked with the pad; a Mac keyboard types into it too. The
/// games behind narrow as the search is typed.
struct CabinetSearchView: View {
    @Bindable var browse: CabinetBrowse
    let event: CabinetEvent?
    let resultCount: Int
    let onDone: () -> Void

    @Environment(\.cabinetTheme) private var installed
    @Environment(GamepadInputMonitor.self) private var gamepad
    @State private var focused = 0

    enum Key: Hashable {
        case character(Character)
        case space, delete, clear, done
    }

    static let columns = 10
    static let keys: [Key] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".map(Key.character) + [.space, .delete, .clear, .done]

    var body: some View {
        let theme = installed.theme
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.palette.accent.color)
                Text(browse.search.isEmpty ? String(localized: "Search") : browse.search)
                    .foregroundStyle(browse.search.isEmpty ? theme.palette.secondaryText.color : theme.palette.text.color)
                    .lineLimit(1)
                Rectangle()
                    .fill(theme.palette.accent.color)
                    .frame(width: 3, height: theme.typography.bodySize * 1.4)
                Spacer()
                Text("^[\(resultCount) game](inflect: true)")
                    .foregroundStyle(theme.palette.secondaryText.color)
                    .monospacedDigit()
            }
            .font(theme.largeFont())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(theme.palette.surface.color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<(Self.keys.count / Self.columns), id: \.self) { row in
                    GridRow {
                        ForEach(0..<Self.columns, id: \.self) { column in
                            let index = row * Self.columns + column
                            keyView(Self.keys[index], isFocused: index == focused, theme: theme)
                                .onTapGesture {
                                    focused = index
                                    press(Self.keys[index])
                                }
                        }
                    }
                }
            }

            HStack(spacing: 28) {
                // On the keyboard, typing types and Delete deletes.
                if gamepad.glyphFamily == .keyboard {
                    Label("Delete", glyph: .symbol("delete.left"))
                    Label("Done", glyph: gamepad.backGlyph)
                } else {
                    Label("Type", glyph: gamepad.confirmGlyph)
                    Label("Delete", glyph: gamepad.glyph(for: .left))
                    Label("Done", glyph: gamepad.backGlyph)
                }
            }
            .font(theme.bodyFont())
            .foregroundStyle(theme.palette.secondaryText.color)
        }
        .padding(28)
        .frame(maxWidth: 900)
        .background(theme.palette.background.color.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.palette.accent.color.opacity(0.35))
        }
        .shadow(color: .black.opacity(0.5), radius: 40)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: event) { _, newEvent in
            if let newEvent { handle(newEvent.command) }
        }
    }

    private func keyView(_ key: Key, isFocused: Bool, theme: CabinetTheme) -> some View {
        Group {
            switch key {
            case .character(let character): Text(String(character))
            case .space: Image(systemName: "space")
            case .delete: Image(systemName: "delete.left")
            case .clear: Image(systemName: "xmark")
            case .done: Image(systemName: "checkmark")
            }
        }
        .font(theme.largeFont(isFocused ? .bold : .medium))
        .frame(width: 64, height: 54)
        .foregroundStyle(isFocused ? theme.palette.background.color : theme.palette.text.color)
        .background(isFocused ? theme.palette.accent.color : theme.palette.surface.color,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isFocused ? 1.08 : 1)
        .animation(.snappy(duration: 0.12), value: isFocused)
    }

    private func handle(_ command: CabinetEvent.Command) {
        switch command {
        case .move(let direction):
            focused = GridNavigation.index(movingFrom: focused, direction: direction,
                                           itemCount: Self.keys.count, columns: Self.columns) ?? focused
        case .activate: press(Self.keys[focused])
        case .details: press(.delete)
        case .search, .back: onDone()
        case .character(let character): browse.search.append(character)
        case .deleteCharacter: press(.delete)
        default: break
        }
    }

    private func press(_ key: Key) {
        switch key {
        case .character(let character): browse.search.append(character)
        case .space: if !browse.search.isEmpty, browse.search.last != " " { browse.search.append(" ") }
        case .delete: if !browse.search.isEmpty { browse.search.removeLast() }
        case .clear: browse.search = ""
        case .done: onDone()
        }
    }
}
