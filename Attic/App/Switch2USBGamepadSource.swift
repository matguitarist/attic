import Foundation
import IOKit
import IOKit.hid
import OSLog
import IOUSBHost
import AtticModels

/// Reads Nintendo's Switch 2 controllers over USB.
///
/// The pad appears to macOS as a HID device that sends nothing (see
/// `Switch2Pad`). When one is plugged in, this sends the start-up
/// sequence on its vendor interface, which no macOS driver claims, then
/// reads the HID input reports that follow through IOHIDManager, without
/// taking the device away from anything else.
///
/// Unlike `XInputUSBGamepadSource` it keeps running in the background: it
/// only listens, and `GamepadInputMonitor` already drops input while
/// Attic isn't frontmost.
final class Switch2USBGamepadSource: @unchecked Sendable {
    /// `log stream --predicate 'subsystem == "com.attic.app" && category == "Switch2USB"'`
    private static let log = Logger(subsystem: "com.attic.app", category: "Switch2USB")

    typealias StateHandler = XInputUSBGamepadSource.StateHandler
    typealias ConnectionHandler = XInputUSBGamepadSource.ConnectionHandler

    private let onState: StateHandler
    private let onConnectionChange: ConnectionHandler
    private let queue = DispatchQueue(label: "com.attic.switch2")
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    /// The pads seen, and the last state each handed on (to skip repeats;
    /// a pad reports about 60 times a second whether anything changed or
    /// not). Only touched on `queue`.
    private var lastStates: [UInt64: XInputPadState?] = [:]

    init(onState: @escaping StateHandler, onConnectionChange: @escaping ConnectionHandler) {
        self.onState = onState
        self.onConnectionChange = onConnectionChange
    }

    /// Everything is set up on `queue` and every callback arrives there:
    /// activating the manager reports the pads already plugged in right
    /// away, on whatever thread activates it.
    func start() {
        queue.async { [self] in setUp() }
    }

    private func setUp() {
        let matching = Switch2Pad.productIDs.map {
            [kIOHIDVendorIDKey: Switch2Pad.vendorID, kIOHIDProductIDKey: $0] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<Switch2USBGamepadSource>.fromOpaque(context).takeUnretainedValue().deviceAppeared(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<Switch2USBGamepadSource>.fromOpaque(context).takeUnretainedValue().deviceDisappeared(device)
        }, context)
        // On the manager, before it's activated: a callback can't be added
        // to a device once the manager has activated it (that's a crash).
        IOHIDManagerRegisterInputReportCallback(manager, { context, _, sender, _, _, report, length in
            guard let context, let sender else { return }
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            let bytes = [UInt8](UnsafeBufferPointer(start: report, count: length))
            Unmanaged<Switch2USBGamepadSource>.fromOpaque(context).takeUnretainedValue().received(bytes, from: device)
        }, context)
        IOHIDManagerSetDispatchQueue(manager, queue)
        // Opens each pad without seizing it, so reports reach the callback
        // and still reach anything else reading it.
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess { Self.log.error("open failed: \(result)") }
        IOHIDManagerActivate(manager)
        Self.log.info("start: watching for Switch 2 controllers")
    }

    // MARK: - Devices

    private func deviceAppeared(_ device: IOHIDDevice) {
        let id = Self.id(of: device)
        guard lastStates[id] == nil else { return }
        lastStates[id] = .some(nil)
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Switch 2 Controller"
        Self.log.notice("found \(name, privacy: .public) (\(id))")

        let onConnectionChange = onConnectionChange
        DispatchQueue.main.async { MainActor.assumeIsolated { onConnectionChange(id, name) } }

        // The sequence takes most of a second, so it runs off the queue
        // the reports arrive on.
        DispatchQueue.global(qos: .userInitiated).async { Self.startPads() }
    }

    private func deviceDisappeared(_ device: IOHIDDevice) {
        let id = Self.id(of: device)
        lastStates.removeValue(forKey: id)
        Self.log.notice("lost \(id)")
        let onConnectionChange = onConnectionChange
        DispatchQueue.main.async { MainActor.assumeIsolated { onConnectionChange(id, nil) } }
    }

    private func received(_ report: [UInt8], from device: IOHIDDevice) {
        let id = Self.id(of: device)
        if case .some(.none) = lastStates[id] {
            Self.log.notice("first report from \(id): \(report.count) bytes, type \(report.first ?? 0)")
        }
        guard let state = XInputPadState(switch2Report: report) else { return }
        guard let last = lastStates[id], state != last else { return }
        lastStates[id] = state
        let onState = onState
        DispatchQueue.main.async { MainActor.assumeIsolated { onState(id, state) } }
    }

    private static func id(of device: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return id
    }

    // MARK: - Start-up

    /// Sends the start-up sequence to every Switch 2 controller's vendor
    /// interface. A few tries, since that interface can register a moment
    /// after the HID one. Sending it to a pad already started is harmless.
    private static func startPads() {
        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.5) }
            let interfaces = commandInterfaces()
            guard !interfaces.isEmpty else { continue }
            for service in interfaces {
                defer { IOObjectRelease(service) }
                do {
                    try sendStartSequence(to: service)
                    log.notice("started a pad")
                } catch {
                    log.error("start failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        }
        log.error("no command interface found")
    }

    private static func commandInterfaces() -> [io_service_t] {
        var found: [io_service_t] = []
        for productID in Switch2Pad.productIDs {
            let matching = IOServiceMatching("IOUSBHostInterface") as NSMutableDictionary
            matching["IOPropertyMatch"] = [
                "idVendor": Switch2Pad.vendorID,
                "idProduct": productID,
                "bInterfaceNumber": Switch2Pad.commandInterfaceNumber,
            ]
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { continue }
            while case let service = IOIteratorNext(iterator), service != 0 { found.append(service) }
            IOObjectRelease(iterator)
        }
        return found
    }

    private static func sendStartSequence(to service: io_service_t) throws {
        let interface = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
        defer { interface.destroy() }
        let (outAddress, inAddress) = bulkEndpoints(of: interface)
        guard let outAddress else { throw CocoaError(.featureUnsupported) }
        log.debug("endpoints out \(outAddress) in \(inAddress ?? 0)")
        let outPipe = try interface.copyPipe(withAddress: Int(outAddress))
        let inPipe = inAddress.flatMap { try? interface.copyPipe(withAddress: Int($0)) }
        // Plain buffers: this interface won't allocate its own ("Unable
        // to allocate IOData Buffer"), and its bulk pipes, unlike the
        // XInput interrupt pipes, take ordinary ones.
        let reply = NSMutableData(length: 64)!
        for (index, command) in Switch2Pad.startCommands.enumerated() {
            let data = NSMutableData(bytes: command, length: command.count)
            var sent = 0
            do {
                try outPipe.__sendIORequest(with: data, bytesTransferred: &sent, completionTimeout: 1.0)
            } catch {
                log.error("command \(index) failed: \(error as NSError, privacy: .public)")
                throw error
            }
            // Read the reply and drop it, so the next command doesn't
            // queue up behind it.
            var received = 0
            do {
                try inPipe?.__sendIORequest(with: reply, bytesTransferred: &received, completionTimeout: 0.1)
                log.debug("command \(index): sent \(sent), reply \(received)")
            } catch {
                log.debug("command \(index): sent \(sent), no reply (\((error as NSError).code))")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// The command interface's bulk endpoints, from the configuration
    /// descriptor: an interface descriptor (type 4) opens a section, its
    /// endpoint descriptors (type 5) follow.
    private static func bulkEndpoints(of interface: IOUSBHostInterface) -> (out: UInt8?, in: UInt8?) {
        let config = interface.configurationDescriptor
        let total = Int(config.pointee.wTotalLength)
        let bytes = UnsafeRawBufferPointer(start: UnsafeRawPointer(config), count: total)
        var out: UInt8?
        var inbound: UInt8?
        var inCommandInterface = false
        var i = 0
        while i + 2 <= total {
            let length = Int(bytes[i])
            if length < 2 { break }
            let type = bytes[i + 1]
            if type == 0x04, i + 3 <= total {
                inCommandInterface = bytes[i + 2] == UInt8(Switch2Pad.commandInterfaceNumber)
            } else if type == 0x05, inCommandInterface, i + 4 <= total, bytes[i + 3] & 0x03 == 0x02 {
                let address = bytes[i + 2]
                if address & 0x80 != 0 { inbound = address } else { out = address }
            }
            i += length
        }
        return (out, inbound)
    }
}
