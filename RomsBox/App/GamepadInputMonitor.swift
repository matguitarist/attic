import AppKit
import GameController
import Observation
import RomsBoxModels

enum GamepadCommand: Equatable {
    case move(GridMoveDirection)
    /// The confirm button (bottom or right, per Settings › Controller) —
    /// play the selected game.
    case activate
    /// Y / Triangle.
    case toggleFavorite
    /// Shoulder buttons — step through the sidebar's sections and systems.
    case previousSection
    case nextSection
    /// The other of bottom/right — leave Big Box.
    case back
    /// Menu / Start — open or close Big Box.
    case toggleBigBox
}

/// Wraps each command with a sequence number so pressing the same button
/// twice in a row still changes the observed value (and so still fires
/// views' `onChange`).
struct GamepadEvent: Equatable {
    let command: GamepadCommand
    let sequence: Int
}

/// Turns any connected game controller into library-navigation commands.
///
/// Views observe `lastEvent` and handle the commands they own (the grid
/// handles moves/activate/favorite, the browser handles section switching)
/// rather than this class knowing about any view.
///
/// Two input paths feed it:
/// - **GameController**, for everything macOS supports natively (Bluetooth
///   Xbox/PlayStation/Switch pads, the Luna over Bluetooth, MFi…).
/// - **`XInputUSBGamepadSource`**, for wired Xbox 360–protocol pads
///   (including the Luna over USB), which macOS has no driver for.
///
/// Both only deliver input while RomsBox is frontmost — GameController by
/// default (`shouldMonitorBackgroundEvents == false`), the USB source
/// because it's started/stopped with app activation. That's exactly right
/// here: once a game launches and the emulator takes focus, the pad
/// belongs to the game, not the library behind it.
@Observable
@MainActor
final class GamepadInputMonitor {
    private(set) var lastEvent: GamepadEvent?
    /// While Big Box is open it owns the controller; the library window
    /// behind it must ignore events, or one press would act in both.
    var isBigBoxActive = false
    var connectedControllerName: String? {
        gameControllerName ?? usbPadNames.values.sorted().first
    }

    private var gameControllerName: String?
    /// The GameController pad in use, for its button glyphs.
    private var gamepad: GCExtendedGamepad?
    private let controllerSettingsStore: ControllerSettingsStore
    private var usbPadNames: [UInt64: String] = [:]
    private var usbPadStates: [UInt64: XInputPadState] = [:]
    private var usbSource: XInputUSBGamepadSource?

    private var sequence = 0

    /// While set, the next button press is handed here (for button mapping
    /// in Settings) instead of becoming a library command.
    private var buttonCapture: ((PhysicalButton) -> Void)?
    private(set) var isCapturingButton = false
    /// Per input path, so a pad on one path releasing a direction doesn't
    /// cancel a hold on the other; the effective set is their union.
    private var heldDirectionsBySource: [InputSource: Set<GridMoveDirection>] = [:]
    private var heldDirections: Set<GridMoveDirection> = []
    private var repeatTasks: [GridMoveDirection: Task<Void, Never>] = [:]

    private static let stickThreshold: Float = 0.5
    private static let repeatInitialDelay: Duration = .milliseconds(400)
    private static let repeatInterval: Duration = .milliseconds(110)

    private enum InputSource: Hashable {
        case gameController
        case xinputUSB
    }

    init(controllerSettingsStore: ControllerSettingsStore) {
        self.controllerSettingsStore = controllerSettingsStore
        let center = NotificationCenter.default
        // Re-reads `GCController.controllers()` rather than taking the
        // notification's object, which can't be sent across into the main
        // actor under strict concurrency. Re-attaching an already-attached
        // controller just reassigns the same handlers, so this is harmless.
        center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { GCController.controllers().forEach { self?.attach($0) } }
        }
        center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnectedController() }
        }
        GCController.controllers().forEach(attach)

        let usbSource = XInputUSBGamepadSource(
            onState: { [weak self] id, state in self?.handleUSBPad(id, state: state) },
            onConnectionChange: { [weak self] id, name in self?.handleUSBPad(id, name: name) }
        )
        self.usbSource = usbSource
        // Only hold the USB interface while RomsBox is frontmost, so it's
        // free for anything else (an emulator with its own USB support, a
        // third-party driver) the rest of the time.
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            usbSource.start()
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            usbSource.stop()
        }
        if NSApp?.isActive == true { usbSource.start() }
    }

    // MARK: - USB (XInput) pads

    private func handleUSBPad(_ id: UInt64, name: String?) {
        if let name {
            usbPadNames[id] = name
        } else {
            usbPadNames.removeValue(forKey: id)
            usbPadStates.removeValue(forKey: id)
            setHeldDirections(combinedUSBDirections, from: .xinputUSB)
        }
    }

    private func handleUSBPad(_ id: UInt64, state: XInputPadState) {
        let previous = usbPadStates[id] ?? .neutral
        usbPadStates[id] = state

        // Same mapping as the GameController path; edge-triggered.
        let newlyPressed = state.buttons.subtracting(previous.buttons)
        let physical: [(XInputButtons, PhysicalButton)] = [
            (.a, .bottom), (.b, .right), (.x, .left), (.y, .top),
            (.leftShoulder, .l1), (.rightShoulder, .r1), (.leftThumb, .l3), (.rightThumb, .r3),
            (.back, .select), (.start, .start),
            (.dpadUp, .dpadUp), (.dpadDown, .dpadDown), (.dpadLeft, .dpadLeft), (.dpadRight, .dpadRight)
        ]
        for (button, position) in physical where newlyPressed.contains(button) {
            handlePress(position)
        }

        setHeldDirections(combinedUSBDirections, from: .xinputUSB)
    }

    private var combinedUSBDirections: Set<GridMoveDirection> {
        usbPadStates.values.reduce(into: []) { $0.formUnion($1.heldDirections()) }
    }

    // MARK: - GameController pads

    private func attach(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        // Handlers are invoked on `handlerQueue`, main by default — pinned
        // explicitly since every handler below assumes main-actor isolation.
        controller.handlerQueue = .main

        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            MainActor.assumeIsolated { self?.updateDirections(from: gamepad) }
        }
        // GameController names buttons by position (buttonA is always the
        // bottom one, whatever its label), which is what `PhysicalButton`
        // means too; the layout decides at press time which confirms.
        for physical in PhysicalButton.allCases {
            guard let button = Self.element(physical, of: gamepad) else { continue }
            button.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                MainActor.assumeIsolated { self?.handlePress(physical) }
            }
        }

        refreshConnectedController()
    }

    private static func element(_ physical: PhysicalButton, of gamepad: GCExtendedGamepad) -> GCControllerButtonInput? {
        switch physical {
        case .bottom: gamepad.buttonA
        case .right: gamepad.buttonB
        case .left: gamepad.buttonX
        case .top: gamepad.buttonY
        case .l1: gamepad.leftShoulder
        case .r1: gamepad.rightShoulder
        case .l2: gamepad.leftTrigger
        case .r2: gamepad.rightTrigger
        case .l3: gamepad.leftThumbstickButton
        case .r3: gamepad.rightThumbstickButton
        case .select: gamepad.buttonOptions
        case .start: gamepad.buttonMenu
        case .dpadUp: gamepad.dpad.up
        case .dpadDown: gamepad.dpad.down
        case .dpadLeft: gamepad.dpad.left
        case .dpadRight: gamepad.dpad.right
        }
    }

    private func handlePress(_ physical: PhysicalButton) {
        if let capture = buttonCapture {
            guard NSApp.isActive else { return }
            buttonCapture = nil
            isCapturingButton = false
            capture(physical)
            return
        }
        if let command = command(for: physical) { send(command) }
    }

    /// Library commands. D-pad presses aren't here: directions come from
    /// `updateDirections`, which merges the D-pad with the left stick.
    private func command(for physical: PhysicalButton) -> GamepadCommand? {
        switch (physical, controllerSettingsStore.settings.layout) {
        case (.bottom, .classic), (.right, .nintendo): .activate
        case (.right, .classic), (.bottom, .nintendo): .back
        case (.top, _): .toggleFavorite
        case (.l1, _): .previousSection
        case (.r1, _): .nextSection
        case (.start, _): .toggleBigBox
        default: nil
        }
    }

    // MARK: - Button capture

    /// Hands the next button pressed on any controller to `handler`.
    func captureNextButton(_ handler: @escaping (PhysicalButton) -> Void) {
        releaseAllDirections()
        buttonCapture = handler
        isCapturingButton = true
    }

    func cancelButtonCapture() {
        buttonCapture = nil
        isCapturingButton = false
    }

    /// The connected pad's own glyph for `physical`, else a generic one.
    func symbol(for physical: PhysicalButton) -> String {
        let fallback = switch physical {
        case .bottom: "a.circle"
        case .right: "b.circle"
        case .left: "x.circle"
        case .top: "y.circle"
        case .l1: "lb.rectangle.roundedbottom"
        case .r1: "rb.rectangle.roundedbottom"
        case .l2: "lt.rectangle.roundedtop"
        case .r2: "rt.rectangle.roundedtop"
        case .l3: "l.joystick.press.down"
        case .r3: "r.joystick.press.down"
        case .select: "rectangle.fill.on.rectangle.fill"
        case .start: "line.3.horizontal.circle"
        case .dpadUp: "dpad.up.filled"
        case .dpadDown: "dpad.down.filled"
        case .dpadLeft: "dpad.left.filled"
        case .dpadRight: "dpad.right.filled"
        }
        let name = gamepad.flatMap { Self.element(physical, of: $0)?.sfSymbolsName } ?? fallback
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "circle"
    }

    /// SF Symbols for the confirm, back and favorite buttons as labeled on
    /// the connected pad (A/B/Y on Xbox-style pads, Cross/Circle/Triangle on
    /// PlayStation ones…), for on-screen hints.
    var confirmButtonSymbol: String {
        glyph(controllerSettingsStore.settings.layout == .classic ? \.buttonA : \.buttonB,
              fallback: controllerSettingsStore.settings.layout == .classic ? "a.circle" : "b.circle")
    }

    var backButtonSymbol: String {
        glyph(controllerSettingsStore.settings.layout == .classic ? \.buttonB : \.buttonA,
              fallback: controllerSettingsStore.settings.layout == .classic ? "b.circle" : "a.circle")
    }

    var favoriteButtonSymbol: String {
        glyph(\.buttonY, fallback: "y.circle")
    }

    private func glyph(_ button: KeyPath<GCExtendedGamepad, GCControllerButtonInput>, fallback: String) -> String {
        let name = gamepad?[keyPath: button].sfSymbolsName ?? fallback
        let filled = name + ".fill"
        return NSImage(systemSymbolName: filled, accessibilityDescription: nil) != nil ? filled : name
    }

    private func refreshConnectedController() {
        let controller = GCController.controllers().first { $0.extendedGamepad != nil }
        gamepad = controller?.extendedGamepad
        gameControllerName = controller.map { $0.vendorName ?? "Game Controller" }
        if controller == nil {
            setHeldDirections([], from: .gameController)
        }
    }

    /// Recomputes held directions from the whole pad on every change, so
    /// the d-pad and left stick behave as one input and diagonal stick
    /// noise doesn't produce phantom presses/releases.
    private func updateDirections(from gamepad: GCExtendedGamepad) {
        let dpad = gamepad.dpad
        let stick = gamepad.leftThumbstick
        var held: Set<GridMoveDirection> = []
        if dpad.up.isPressed || stick.yAxis.value > Self.stickThreshold { held.insert(.up) }
        if dpad.down.isPressed || stick.yAxis.value < -Self.stickThreshold { held.insert(.down) }
        if dpad.left.isPressed || stick.xAxis.value < -Self.stickThreshold { held.insert(.left) }
        if dpad.right.isPressed || stick.xAxis.value > Self.stickThreshold { held.insert(.right) }
        setHeldDirections(held, from: .gameController)
    }

    // MARK: - Shared

    /// Fires a move for each newly held direction and starts its
    /// hold-to-repeat; cancels the repeat for each released one.
    private func setHeldDirections(_ sourceHeld: Set<GridMoveDirection>, from source: InputSource) {
        heldDirectionsBySource[source] = sourceHeld
        let held = heldDirectionsBySource.values.reduce(into: Set<GridMoveDirection>()) { $0.formUnion($1) }

        for direction in heldDirections.subtracting(held) {
            repeatTasks.removeValue(forKey: direction)?.cancel()
        }
        for direction in held.subtracting(heldDirections) {
            send(.move(direction))
            repeatTasks[direction] = Task { [weak self] in
                try? await Task.sleep(for: Self.repeatInitialDelay)
                while !Task.isCancelled {
                    self?.send(.move(direction))
                    try? await Task.sleep(for: Self.repeatInterval)
                }
            }
        }
        heldDirections = held
    }

    private func releaseAllDirections() {
        repeatTasks.values.forEach { $0.cancel() }
        repeatTasks.removeAll()
        heldDirections.removeAll()
        heldDirectionsBySource.removeAll()
    }

    private func send(_ command: GamepadCommand) {
        // Mapping a button in Settings: the pad shouldn't also drive the library.
        guard !isCapturingButton else { return }
        // Belt and braces alongside GameController's own foreground-only
        // delivery: a held-direction repeat task could otherwise keep
        // firing after the app loses focus mid-hold.
        guard NSApp.isActive else {
            releaseAllDirections()
            return
        }
        sequence += 1
        lastEvent = GamepadEvent(command: command, sequence: sequence)
    }
}
