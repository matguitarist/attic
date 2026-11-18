import SwiftUI
import AtticModels

/// Kid Mode, like EmulationStation's Kid and Kiosk modes: Cabinet Mode
/// keeps to one collection (or every game), its menu only finds games, and
/// leaving it or quitting asks for a four-digit PIN. Set in Settings ›
/// Cabinet Mode. It guards the controller's ways out; a Mac keyboard's
/// ⌘Q still quits.
enum CabinetKidMode {
    static let enabledKey = "cabinetKidMode"
    /// The collection shown, by its ID; empty for every game.
    static let collectionKey = "cabinetKidCollection"
    static let pinKey = "cabinetKidPIN"

    static func isValidPIN(_ pin: String) -> Bool {
        pin.count == 4 && pin.allSatisfy(\.isASCIIDigit)
    }

    /// On only with a PIN to get out.
    static var isOn: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: enabledKey) && isValidPIN(defaults.string(forKey: pinKey) ?? "")
    }

    static var pin: String { UserDefaults.standard.string(forKey: pinKey) ?? "" }

    /// The sections a child sees: the chosen collection only, when it's
    /// still there and has games.
    static func sections(_ sections: [CabinetSection], collectionID: String) -> [CabinetSection] {
        guard let id = UUID(uuidString: collectionID) else { return sections }
        let kept = sections.filter { $0.selection == .collection(id) }
        return kept.isEmpty ? sections : kept
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

/// Four digits set with the pad: left and right pick a digit, up and down
/// change it, A checks the PIN, B cancels. A keyboard's digits type it.
struct CabinetPINView: View {
    let event: CabinetEvent?
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @Environment(\.cabinetTheme) private var installed
    @State private var digits = [0, 0, 0, 0]
    @State private var focused = 0
    @State private var isWrong = false

    var body: some View {
        let theme = installed.theme
        VStack(spacing: 24) {
            Text("Enter the PIN")
                .font(theme.font(size: theme.typography.titleSize * 0.8, weight: .bold))
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    let isFocused = index == focused
                    VStack(spacing: 6) {
                        Image(systemName: "chevron.up").opacity(isFocused ? 1 : 0)
                        Text(verbatim: String(digits[index]))
                            .font(theme.font(size: 56, weight: .bold).monospacedDigit())
                            .frame(width: 84, height: 96)
                            .background(theme.palette.surface.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                if isFocused {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.palette.accent.color, lineWidth: 3)
                                }
                            }
                        Image(systemName: "chevron.down").opacity(isFocused ? 1 : 0)
                    }
                    .foregroundStyle(theme.palette.text.color)
                    .onTapGesture { focused = index }
                }
            }
            .modifier(Shake(amount: isWrong ? 1 : 0))
            Text(isWrong ? String(localized: "That's not the PIN.") : String(localized: "A to confirm, B to cancel"))
                .font(theme.bodyFont())
                .foregroundStyle(theme.palette.secondaryText.color)
        }
        .padding(40)
        .background(theme.palette.background.color.opacity(0.95), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.5))
        .onChange(of: event) { _, newEvent in
            guard let command = newEvent?.command else { return }
            isWrong = false
            switch command {
            case .move(.left): focused = max(0, focused - 1)
            case .move(.right): focused = min(3, focused + 1)
            case .move(.up): digits[focused] = (digits[focused] + 1) % 10
            case .move(.down): digits[focused] = (digits[focused] + 9) % 10
            case .character(let character):
                if let digit = character.wholeNumberValue, character.isASCIIDigit {
                    digits[focused] = digit
                    if focused < 3 { focused += 1 } else { check() }
                }
            case .deleteCharacter: focused = max(0, focused - 1)
            case .activate: check()
            case .back, .menu: onCancel()
            default: break
            }
        }
    }

    private func check() {
        if digits.map(String.init).joined() == CabinetKidMode.pin {
            onSuccess()
        } else {
            withAnimation(.default) { isWrong = true }
            digits = [0, 0, 0, 0]
            focused = 0
        }
    }

    private struct Shake: GeometryEffect {
        var amount: CGFloat
        var animatableData: CGFloat {
            get { amount }
            set { amount = newValue }
        }
        func effectValue(size: CGSize) -> ProjectionTransform {
            ProjectionTransform(CGAffineTransform(translationX: 12 * sin(amount * .pi * 6), y: 0))
        }
    }
}
