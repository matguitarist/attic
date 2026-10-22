import Foundation

/// Keeps one computed value until what it's computed from changes.
///
/// Views build their game lists in `body`, which runs on every redraw — a
/// press, a focus move — and sorting or filtering thousands of games each
/// time is what made long lists sluggish. Held in `@State`, so it lasts as
/// long as the view; not observable, so filling it never redraws anything.
@MainActor
final class Memo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func callAsFunction(_ key: Key, compute: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let computed = compute()
        self.key = key
        value = computed
        return computed
    }
}

/// The same games, in the same order: by identity, which is quick. Their
/// own equality compares model identifiers, and doing that for thousands
/// of games on every redraw was slower than the sort it was saving.
func sameGames<T: AnyObject>(_ a: [T], _ b: [T]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0 === $1 }
}
