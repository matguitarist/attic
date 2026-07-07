import SwiftUI

/// A minimal draggable-divider horizontal split, used in place of
/// `HSplitView` — that gave a fixed 50/50 initial split with no visible
/// way to actually drag it in practice, rather than honoring the intended
/// ~2:1 ratio and remaining resizable. Building this by hand with a plain
/// `DragGesture` sidesteps whatever's going on there and keeps both the
/// initial ratio and the drag behavior fully under our own control.
struct ResizableHSplit<Leading: View, Trailing: View>: View {
    @State private var trailingWidth: CGFloat
    // `DragGesture`'s `.translation` is cumulative from the start of the
    // current drag, not incremental since the last callback — the width
    // has to be computed from a fixed snapshot taken at drag start, not by
    // repeatedly subtracting translation from the already-mutated
    // `trailingWidth` on every `.onChanged` call.
    @State private var widthAtDragStart: CGFloat?
    private let minTrailingWidth: CGFloat
    private let maxTrailingWidth: CGFloat
    private let leading: Leading
    private let trailing: Trailing

    init(
        initialTrailingWidth: CGFloat,
        minTrailingWidth: CGFloat,
        maxTrailingWidth: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        _trailingWidth = State(initialValue: initialTrailingWidth)
        self.minTrailingWidth = minTrailingWidth
        self.maxTrailingWidth = maxTrailingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack {
                Divider()
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        if isHovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let base = widthAtDragStart ?? trailingWidth
                                if widthAtDragStart == nil { widthAtDragStart = base }
                                let proposed = base - value.translation.width
                                trailingWidth = min(max(proposed, minTrailingWidth), maxTrailingWidth)
                            }
                            .onEnded { _ in
                                widthAtDragStart = nil
                            }
                    )
            }
            .frame(width: 9)

            trailing
                .frame(width: trailingWidth)
                .frame(maxHeight: .infinity)
        }
    }
}
