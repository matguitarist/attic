import SwiftUI

/// Placeholder root view. Replaced by the NavigationSplitView library
/// browser in Phase 6.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("RomsBox")
                .font(.title)
        }
        .frame(width: 480, height: 320)
    }
}

#Preview {
    ContentView()
}
