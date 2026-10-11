import AppKit
import GameController
import Observation
import RomsBoxModels

enum GamepadCommand: Equatable {
    case move(GridMoveDirection)
    /// A / Cross — play the selected game.
    case activate
    /// Y / Triangle.
    case toggleFavorite
    /// Shoulder buttons — step through the sidebar's sections and systems.
    case previousSection
    case nextSection
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
    var connectedControllerName: String? {
        gameControllerName ?? usbPadNames.values.sorted().first
    }

    private var gameControllerName: String?
    private var usbPadNames: [UInt64: String] = [:]
    private var usbPadStates: [UInt64: XInputPadState] = [:]
    private var usbSource: XInputUSBGamepadSource?

    private var sequence = 0
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

    init() {
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

        // Same mapping as the GameController path: A plays, Y favorites,
        // shoulders switch sections. Edge-triggered, like `bind(_:to:)`.
        let newlyPressed = state.buttons.subtracting(previous.buttons)
        if newlyPressed.contains(.a) { send(.activate) }
        if newlyPressed.contains(.y) { send(.toggleFavorite) }
        if newlyPressed.contains(.leftShoulder) { send(.previousSection) }
        if newlyPressed.contains(.rightShoulder) { send(.nextSection) }

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
        bind(gamepad.buttonA, to: .activate)
        bind(gamepad.buttonY, to: .toggleFavorite)
        bind(gamepad.leftShoulder, to: .previousSection)
        bind(gamepad.rightShoulder, to: .nextSection)

        refreshConnectedController()
    }

    private func bind(_ button: GCControllerButtonInput, to command: GamepadCommand) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.send(command) }
        }
    }

    private func refreshConnectedController() {
        let controller = GCController.controllers().first { $0.extendedGamepad != nil }
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
