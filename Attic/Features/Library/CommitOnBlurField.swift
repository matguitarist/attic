import SwiftUI

/// Edits a local draft and only hands the result back via `onCommit` when
/// the user is done — on Return, on losing focus, or when the field goes
/// away — and only if the text actually changed.
///
/// The detail panel used to bind its fields straight to the model, which
/// saved the SwiftData store on every keystroke and flagged the game as
/// `metadataManuallyEdited` the moment a field was merely touched, even if
/// the text ended up identical.
///
/// Callers should give the surrounding view an identity tied to the game
/// being edited (`.id(game.persistentModelID)`), so switching games tears
/// these fields down — committing any pending draft to the *old* game —
/// instead of reusing them with a stale draft for the new one.
struct CommitOnBlurField<Content: View>: View {
    let value: String
    let isValid: (String) -> Bool
    let onCommit: (String) -> Void
    @ViewBuilder let content: (Binding<String>, FocusState<Bool>.Binding) -> Content

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        value: String,
        isValid: @escaping (String) -> Bool = { _ in true },
        onCommit: @escaping (String) -> Void,
        @ViewBuilder content: @escaping (Binding<String>, FocusState<Bool>.Binding) -> Content
    ) {
        self.value = value
        self.isValid = isValid
        self.onCommit = onCommit
        self.content = content
        _draft = State(initialValue: value)
    }

    var body: some View {
        content($draft, $isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            // Picks up changes made elsewhere (e.g. a scrape finishing)
            // while the user isn't mid-edit.
            .onChange(of: value) { _, newValue in
                if !isFocused { draft = newValue }
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        guard draft != value else { return }
        guard isValid(draft) else {
            draft = value
            return
        }
        onCommit(draft)
    }
}
