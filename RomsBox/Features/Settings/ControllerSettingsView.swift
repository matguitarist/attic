import SwiftUI
import RomsBoxModels

/// Settings › Controller: one global setup for every controller, plus
/// profiles to save and restore it.
struct ControllerSettingsView: View {
    @Environment(ControllerSettingsStore.self) private var store
    @Environment(GamepadInputMonitor.self) private var gamepad

    @State private var isNamingProfile = false
    @State private var newProfileName = ""

    var body: some View {
        @Bindable var store = store

        Form {
            Section {
                Picker("Confirm Button", selection: $store.settings.layout) {
                    Text("Bottom — Xbox, PlayStation").tag(ButtonLayout.classic)
                    Text("Right — Nintendo, Switch").tag(ButtonLayout.nintendo)
                }
                LabeledContent("Confirm / Back") {
                    HStack(spacing: 6) {
                        Image(systemName: gamepad.confirmButtonSymbol)
                        Text("/")
                        Image(systemName: gamepad.backButtonSymbol)
                    }
                    .font(.title3)
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Used in RomsBox, Big Box and RetroArch's menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Left stick also works as the D-pad", isOn: $store.settings.leftStickAsDPad)
                Toggle("Quit games with Select + Start", isOn: $store.settings.quitWithSelectStart)
            } header: {
                Text("In Games")
            } footer: {
                Text("The left stick option applies to RetroArch games; Select + Start also quits DuckStation. Games save normally on the way out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ButtonMappingSection(mapping: $store.settings.buttonMapping)

            Section {
                ForEach(ControllerSettingsStore.presets) { profile in
                    profileRow(profile, deletable: false)
                }
                ForEach(store.savedProfiles) { profile in
                    profileRow(profile, deletable: true)
                }
                Button("Save Current Settings as Profile…") {
                    newProfileName = ""
                    isNamingProfile = true
                }
            } header: {
                Text("Profiles")
            } footer: {
                if let error = store.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text("Saved profiles are kept in the Emulation folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Save Profile", isPresented: $isNamingProfile) {
            TextField("Name", text: $newProfileName)
            Button("Save") { store.saveCurrentSettings(as: newProfileName) }
                .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saving with an existing profile's name replaces it.")
        }
    }

    private func profileRow(_ profile: ControllerProfile, deletable: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                Text(summary(of: profile.settings))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.matchingProfile?.id == profile.id {
                Label("In Use", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .help("In Use")
            } else {
                Button("Load") { store.apply(profile) }
            }
            if deletable {
                Button(role: .destructive) {
                    store.delete(profile)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
    }

    private func summary(of settings: ControllerSettings) -> String {
        var parts = [settings.layout == .classic
            ? String(localized: "Bottom confirms")
            : String(localized: "Right confirms")]
        if settings.buttonMapping == .faceButtonsSwapped {
            parts.append(String(localized: "A/B swapped in games"))
        } else if !settings.buttonMapping.isDefault {
            parts.append(String(localized: "Custom buttons"))
        }
        if settings.leftStickAsDPad { parts.append(String(localized: "Stick as D-pad")) }
        if !settings.quitWithSelectStart { parts.append(String(localized: "No quit combo")) }
        return parts.formatted(.list(type: .and, width: .narrow))
    }
}

/// Which controller button presses each game button — RetroArch's
/// standard pad, named like a Super Nintendo pad. Pick from a menu, or
/// press Assign and then the button on the controller.
private struct ButtonMappingSection: View {
    @Binding var mapping: ButtonMapping
    @Environment(GamepadInputMonitor.self) private var gamepad
    @State private var capturing: RetroPadButton?

    private static let order: [RetroPadButton] = [.a, .b, .x, .y, .l, .r, .l2, .r2, .l3, .r3, .select, .start, .up, .down, .left, .right]

    var body: some View {
        Section {
            ForEach(Self.order, id: \.self) { button in
                LabeledContent(button.title) {
                    HStack(spacing: 8) {
                        if capturing == button {
                            Text("Press a button…")
                                .foregroundStyle(.tint)
                            Button("Cancel") { stopCapture() }
                        } else {
                            Picker(button.title, selection: binding(for: button)) {
                                ForEach(PhysicalButton.allCases, id: \.self) { physical in
                                    Label(physical.title, systemImage: gamepad.symbol(for: physical))
                                        .tag(physical)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            Button("Assign…") { startCapture(for: button) }
                                .help("Press Assign, then the button on your controller")
                        }
                    }
                }
                .fontWeight(mapping.overrides[button] == nil ? .regular : .semibold)
            }
            HStack {
                Button("Swap A/B and X/Y") { mapping = .faceButtonsSwapped }
                    .disabled(mapping == .faceButtonsSwapped)
                Spacer()
                Button("Reset to Default") { mapping = .default }
                    .disabled(mapping.isDefault)
            }
        } header: {
            Text("Button Mapping")
        } footer: {
            Text("Buttons are named like on a Super Nintendo pad, RetroArch's standard. By default games use buttons by position, like the console's own pad: on an Xbox-style pad, a Nintendo game's A is the right button. Applies to every player in RetroArch games, and to DuckStation. Changed buttons are shown in bold.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDisappear { stopCapture() }
    }

    private func binding(for button: RetroPadButton) -> Binding<PhysicalButton> {
        Binding(get: { mapping.physical(for: button) }, set: { mapping.set($0, for: button) })
    }

    private func startCapture(for button: RetroPadButton) {
        capturing = button
        gamepad.captureNextButton { physical in
            mapping.set(physical, for: button)
            capturing = nil
        }
    }

    private func stopCapture() {
        gamepad.cancelButtonCapture()
        capturing = nil
    }
}

extension RetroPadButton {
    var title: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .l: "L"
        case .r: "R"
        case .l2: "L2"
        case .r2: "R2"
        case .l3: "L3"
        case .r3: "R3"
        case .select: "Select"
        case .start: "Start"
        case .up: String(localized: "D-pad Up")
        case .down: String(localized: "D-pad Down")
        case .left: String(localized: "D-pad Left")
        case .right: String(localized: "D-pad Right")
        }
    }
}

extension PhysicalButton {
    var title: String {
        switch self {
        case .bottom: String(localized: "Bottom (A / Cross)")
        case .right: String(localized: "Right (B / Circle)")
        case .left: String(localized: "Left (X / Square)")
        case .top: String(localized: "Top (Y / Triangle)")
        case .l1: "L1 / LB"
        case .r1: "R1 / RB"
        case .l2: "L2 / LT"
        case .r2: "R2 / RT"
        case .l3: String(localized: "Left Stick Click")
        case .r3: String(localized: "Right Stick Click")
        case .select: "Select / View"
        case .start: "Start / Menu"
        case .dpadUp: String(localized: "D-pad Up")
        case .dpadDown: String(localized: "D-pad Down")
        case .dpadLeft: String(localized: "D-pad Left")
        case .dpadRight: String(localized: "D-pad Right")
        }
    }
}
