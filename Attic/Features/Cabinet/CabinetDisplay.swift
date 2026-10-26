import AppKit

/// The screen Cabinet Mode plays on, kept by name: an Apple TV the Mac
/// extends its desktop to over AirPlay, a TV on HDMI. macOS gives apps no
/// way to start AirPlay, so the screen is connected from Control Center's
/// Screen Mirroring (as an extended display, not a mirror); from then on
/// Cabinet Mode, and the games RetroArch runs, go to it.
enum CabinetDisplay {
    static let key = "cabinetDisplay"

    /// The chosen screen's name; empty for the one Attic is on.
    static var chosenName: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The chosen screen, while it's connected.
    static var screen: NSScreen? {
        let name = chosenName
        guard !name.isEmpty else { return nil }
        return NSScreen.screens.first { $0.localizedName == name }
    }

    /// RetroArch's number for the screen Cabinet Mode is on (from 1; 0 lets
    /// it choose), while Cabinet Mode is open on a chosen screen.
    @MainActor static var retroArchMonitorIndex: Int? {
        guard let window = CabinetWindows.cabinet, window.isVisible, let screen = screen ?? window.screen,
              !chosenName.isEmpty, let index = NSScreen.screens.firstIndex(of: screen) else { return nil }
        return index + 1
    }

    @MainActor private static var exitObserver: NSObjectProtocol?

    /// Takes the Cabinet window to the chosen screen, in full screen there.
    @MainActor
    static func move(_ window: NSWindow) {
        guard let target = screen, window.screen != target else { return }
        guard window.styleMask.contains(.fullScreen) else {
            place(window, on: target)
            return
        }
        // Leaving full screen animates; move once it's done.
        if let exitObserver { NotificationCenter.default.removeObserver(exitObserver) }
        exitObserver = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                if let exitObserver { NotificationCenter.default.removeObserver(exitObserver) }
                exitObserver = nil
                if let target = screen { place(window, on: target) }
            }
        }
        window.toggleFullScreen(nil)
    }

    /// Puts a window that isn't full screen on `screen`, then full screen.
    @MainActor
    static func place(_ window: NSWindow, on screen: NSScreen) {
        window.setFrame(screen.visibleFrame, display: true)
        DispatchQueue.main.async { window.toggleFullScreen(nil) }
    }

    /// Displays settings, where an AirPlay screen is connected too.
    static func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
