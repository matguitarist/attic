import AppKit
import SwiftUI
import GameController
import Observation
import AtticModels

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
    /// The other of bottom/right — leave Cabinet Mode.
    case back
    /// Menu / Start — open or close Cabinet Mode.
    case toggleCabinet
    /// X / Square — the game's page in Cabinet Mode.
    case details
    /// Select / View — search Cabinet Mode.
    case search
    /// Right stick click — a random game.
    case random
    /// L2 / R2 — the previous or next letter.
    case previousLetter
    case nextLetter
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
/// - **`Switch2USBGamepadSource`**, for Nintendo's Switch 2 controllers
///   over USB, which macOS doesn't support either.
///
/// Both only deliver input while Attic is frontmost — GameController by
/// default (`shouldMonitorBackgroundEvents == false`), the USB source
/// because it's started/stopped with app activation. That's exactly right
/// here: once a game launches and the emulator takes focus, the pad
/// belongs to the game, not the library behind it.
@Observable
@MainActor
final class GamepadInputMonitor {
    /// For the library window.
    private(set) var lastEvent: GamepadEvent?
    /// For Cabinet Mode, while it's open. A channel of its own, not just
    /// a flag the library checks: everything reading `lastEvent` gets
    /// rebuilt when it changes, and rebuilding the library window behind
    /// on every press made the pad lag in Cabinet Mode.
    private(set) var cabinetEvent: GamepadEvent?
    /// While Cabinet Mode is open it owns the controller; the library window
    /// behind it must ignore events, or one press would act in both.
    var isCabinetActive = false
    var connectedControllerName: String? {
        gameControllerName ?? usbPadNames.values.sorted().first
    }

    private var gameControllerName: String?
    /// What the GameController pad in use calls itself, for its buttons.
    private var gameControllerCategory: String?
    private let controllerSettingsStore: ControllerSettingsStore
    private var usbPadNames: [UInt64: String] = [:]
    private var usbPadStates: [UInt64: XInputPadState] = [:]
    private var usbSource: XInputUSBGamepadSource?
    private var switch2Source: Switch2USBGamepadSource?

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
    /// Holding a direction repeats like a keyboard: a short wait, then
    /// faster the longer it's held, so long lists go by quickly.
    private static let repeatInitialDelay: Duration = .milliseconds(280)
    private static let repeatIntervals: [Duration] = [.milliseconds(90), .milliseconds(70), .milliseconds(55), .milliseconds(40)]
    private static let repeatsPerStep = 6

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
        // Only hold the USB interface while Attic is frontmost, so it's
        // free for anything else (an emulator with its own USB support, a
        // third-party driver) the rest of the time.
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            usbSource.start()
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            usbSource.stop()
        }
        if NSApp?.isActive == true { usbSource.start() }

        // Switch 2 pads become the same kind of state as the XInput ones.
        let switch2Source = Switch2USBGamepadSource(
            onState: { [weak self] id, state in self?.handleUSBPad(id, state: state) },
            onConnectionChange: { [weak self] id, name in self?.handleUSBPad(id, name: name) }
        )
        self.switch2Source = switch2Source
        switch2Source.start()
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
        // The triggers are analog, so a press is crossing halfway.
        if state.leftTriggerPressed && !previous.leftTriggerPressed { handlePress(.l2) }
        if state.rightTriggerPressed && !previous.rightTriggerPressed { handlePress(.r2) }

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
        case (.start, _): .toggleCabinet
        case (.left, _): .details
        case (.select, _): .search
        case (.r3, _): .random
        case (.l2, _): .previousLetter
        case (.r2, _): .nextLetter
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

    // MARK: - Button glyphs

    /// Which controller's buttons on-screen hints show; `nil` follows the
    /// one connected. Kept apart from `ControllerSettings`, which profiles
    /// save: what the buttons look like isn't part of a setup.
    var buttonIcons: ControllerFamily? = UserDefaults.standard.string(forKey: "buttonIcons").flatMap(ControllerFamily.init) {
        didSet { UserDefaults.standard.set(buttonIcons?.rawValue, forKey: "buttonIcons") }
    }

    /// The connected controller's family, or the keyboard without one.
    var glyphFamily: ControllerFamily {
        if let buttonIcons { return buttonIcons }
        guard let name = connectedControllerName else { return .keyboard }
        return ControllerFamily.detect(name: name, category: gameControllerCategory)
    }

    /// The controller in use, as an icon.
    var controllerSymbol: String { glyphFamily.symbol }

    /// For places about the pad itself (button mapping, the controller
    /// help), which mean a pad even when the keyboard is in use.
    private var padFamily: ControllerFamily {
        glyphFamily == .keyboard ? .xbox : glyphFamily
    }

    /// `physical` as drawn on the controller in use, or its key.
    func glyph(for physical: PhysicalButton) -> ButtonGlyph {
        glyphFamily.glyph(for: physical, layout: controllerSettingsStore.settings.layout)
    }

    var confirmGlyph: ButtonGlyph { glyph(for: confirmButton) }
    var backGlyph: ButtonGlyph { glyph(for: backButton) }
    var favoriteGlyph: ButtonGlyph { glyph(for: .top) }
    var menuGlyph: ButtonGlyph { glyph(for: .start) }

    /// The pad's SF Symbol for `physical`.
    func symbol(for physical: PhysicalButton) -> String {
        guard case .symbol(let name) = padFamily.glyph(for: physical) else { return "circle" }
        return name
    }

    var confirmButtonSymbol: String { symbol(for: confirmButton) }
    var backButtonSymbol: String { symbol(for: backButton) }
    var favoriteButtonSymbol: String { symbol(for: .top) }

    private var confirmButton: PhysicalButton {
        controllerSettingsStore.settings.layout == .classic ? .bottom : .right
    }

    private var backButton: PhysicalButton {
        controllerSettingsStore.settings.layout == .classic ? .right : .bottom
    }

    private func refreshConnectedController() {
        let controller = GCController.controllers().first { $0.extendedGamepad != nil }
        gameControllerName = controller.map { $0.vendorName ?? "Game Controller" }
        gameControllerCategory = controller?.productCategory
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
                var repeats = 0
                while !Task.isCancelled {
                    self?.send(.move(direction))
                    let step = min(repeats / Self.repeatsPerStep, Self.repeatIntervals.count - 1)
                    repeats += 1
                    try? await Task.sleep(for: Self.repeatIntervals[step])
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
        let event = GamepadEvent(command: command, sequence: sequence)
        if isCabinetActive {
            cabinetEvent = event
        } else {
            lastEvent = event
        }
    }
}

/// Hands the library window's gamepad events to `action`. Whatever reads
/// `lastEvent` in its body is rebuilt on every press, and the library's
/// views are big — the whole grid re-sorted its games each time, which
/// made the pad sluggish — so a small view of its own does the reading.
private struct GamepadEventReceiver: View {
    let action: (GamepadEvent) -> Void

    @Environment(GamepadInputMonitor.self) private var gamepad

    var body: some View {
        Color.clear
            .onChange(of: gamepad.lastEvent) { _, event in
                guard let event, !gamepad.isCabinetActive else { return }
                action(event)
            }
    }
}

extension View {
    /// The library window's gamepad events, without rebuilding this view
    /// for each one.
    func onGamepadEvent(perform action: @escaping (GamepadEvent) -> Void) -> some View {
        background(GamepadEventReceiver(action: action))
    }
}
