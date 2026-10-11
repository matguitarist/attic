import Foundation
import IOKit
import IOUSBHost
import RomsBoxModels

/// Reads XInput (Xbox 360 wired protocol) pads directly over USB.
///
/// macOS ships no driver for these: such a pad — or one emulating it, like
/// the Amazon Luna controller in USB mode — shows up only as an unclaimed
/// vendor-specific USB interface, invisible to GameController and
/// IOHIDManager alike. Since nothing else claims that interface, an
/// ordinary (non-sandboxed) app can open it and read its interrupt-IN pipe
/// itself, which is what this does. Bluetooth pads keep going through
/// GameController; this only fills the USB gap.
///
/// Lifecycle: `start()` opens every XInput interface already attached and
/// watches for new ones; `stop()` releases them all. `GamepadInputMonitor`
/// ties those to app activation, so the interface is only held while
/// RomsBox is frontmost and is free for anything else the rest of the time.
final class XInputUSBGamepadSource: @unchecked Sendable {
    typealias StateHandler = @MainActor (_ deviceID: UInt64, _ state: XInputPadState) -> Void
    typealias ConnectionHandler = @MainActor (_ deviceID: UInt64, _ name: String?) -> Void

    private static let interfaceClass = 0xFF
    private static let interfaceSubClass = 0x5D
    private static let interfaceProtocol = 0x01
    /// "Set LED: player 1". Standard first message to an Xbox 360 pad;
    /// the probe confirmed the Luna answers it with its current state.
    private static let ledPlayerOneMessage: [UInt8] = [0x01, 0x03, 0x06]

    private let onState: StateHandler
    private let onConnectionChange: ConnectionHandler

    private let queue = DispatchQueue(label: "com.romsbox.xinput")
    private let lock = NSLock()
    private var devices: [UInt64: Device] = [:]
    private var notificationPort: IONotificationPortRef?
    private var matchIterator: io_iterator_t = 0

    /// `onConnectionChange` gets a name when a pad is opened and `nil`
    /// when it goes away (unplugged, or released by `stop()`).
    init(onState: @escaping StateHandler, onConnectionChange: @escaping ConnectionHandler) {
        self.onState = onState
        self.onConnectionChange = onConnectionChange
    }

    func start() {
        queue.async { [self] in
            guard notificationPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
            notificationPort = port
            IONotificationPortSetDispatchQueue(port, queue)

            let context = Unmanaged.passUnretained(self).toOpaque()
            let result = IOServiceAddMatchingNotification(
                port,
                kIOFirstMatchNotification,
                IOServiceMatching("IOUSBHostInterface"),
                { context, iterator in
                    guard let context else { return }
                    Unmanaged<XInputUSBGamepadSource>.fromOpaque(context).takeUnretainedValue().drain(iterator)
                },
                context,
                &matchIterator
            )
            // Arms the notification and picks up pads already plugged in.
            if result == KERN_SUCCESS { drain(matchIterator) }
        }
    }

    func stop() {
        queue.async { [self] in
            if matchIterator != 0 {
                IOObjectRelease(matchIterator)
                matchIterator = 0
            }
            if let port = notificationPort {
                IONotificationPortDestroy(port)
                notificationPort = nil
            }
            lock.lock()
            let open = devices
            devices.removeAll()
            lock.unlock()
            for device in open.values { device.close() }
        }
    }

    // MARK: - Discovery

    private func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard Self.isXInputInterface(service) else { continue }
            open(service)
        }
    }

    private static func isXInputInterface(_ service: io_service_t) -> Bool {
        intProperty(service, "bInterfaceClass") == interfaceClass
            && intProperty(service, "bInterfaceSubClass") == interfaceSubClass
            && intProperty(service, "bInterfaceProtocol") == interfaceProtocol
    }

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }

    /// The product name lives on the parent USB device, not the interface.
    private static func productName(of service: io_service_t) -> String? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        return IORegistryEntryCreateCFProperty(parent, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    private func open(_ service: io_service_t) {
        var registryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &registryID)
        lock.lock()
        let alreadyOpen = devices[registryID] != nil
        lock.unlock()
        guard !alreadyOpen else { return }

        let device: Device
        do {
            device = try Device(service: service, id: registryID, queue: queue)
        } catch {
            // Most likely claimed by a third-party driver, which then
            // presumably exposes the pad to GameController itself.
            return
        }
        let name = Self.productName(of: service) ?? "USB Controller"

        lock.lock()
        devices[registryID] = device
        lock.unlock()

        let onConnectionChange = onConnectionChange
        DispatchQueue.main.async { MainActor.assumeIsolated { onConnectionChange(registryID, name) } }

        device.sendOutput(Self.ledPlayerOneMessage)
        startReading(device)
    }

    // MARK: - Reading

    private func startReading(_ device: Device) {
        let onState = onState
        Thread.detachNewThread { [weak self] in
            var lastState: XInputPadState?
            // Blocks until the pad has something to say; ends when the pipe
            // is aborted by `stop()` or errors out because it was unplugged.
            while let report = device.readReport() {
                guard let state = XInputPadState(report: report), state != lastState else { continue }
                lastState = state
                DispatchQueue.main.async { MainActor.assumeIsolated { onState(device.id, state) } }
            }
            self?.deviceDidEnd(device)
        }
    }

    private func deviceDidEnd(_ device: Device) {
        lock.lock()
        let wasTracked = devices.removeValue(forKey: device.id) != nil
        lock.unlock()
        if wasTracked { device.close() }

        let onConnectionChange = onConnectionChange
        let id = device.id
        DispatchQueue.main.async { MainActor.assumeIsolated { onConnectionChange(id, nil) } }
    }

    /// One opened XInput interface and its pipes. Touched from the reader
    /// thread and the source's queue, hence `@unchecked Sendable` — the
    /// IOUSBHost objects are themselves safe to use across threads.
    private final class Device: @unchecked Sendable {
        let id: UInt64
        private let interface: IOUSBHostInterface
        private let inPipe: IOUSBHostPipe
        private let outPipe: IOUSBHostPipe?
        // IOUSBHost requires buffers it allocated itself — a plain
        // NSMutableData fails every request with kIOReturnBadArgument.
        private let readBuffer: NSMutableData

        init(service: io_service_t, id: UInt64, queue: DispatchQueue) throws {
            self.id = id
            interface = try IOUSBHostInterface(__ioService: service, options: [], queue: queue, interestHandler: nil)
            var inPipe: IOUSBHostPipe?
            var outPipe: IOUSBHostPipe?
            for endpoint in 1...15 {
                if inPipe == nil { inPipe = try? interface.copyPipe(withAddress: 0x80 | endpoint) }
                if outPipe == nil { outPipe = try? interface.copyPipe(withAddress: endpoint) }
            }
            guard let inPipe else {
                interface.destroy()
                throw CocoaError(.featureUnsupported)
            }
            self.inPipe = inPipe
            self.outPipe = outPipe
            readBuffer = try interface.ioData(withCapacity: 32)
        }

        /// Interrupt pipes reject any completion timeout other than 0
        /// (again kIOReturnBadArgument), so this blocks indefinitely —
        /// fine on a dedicated thread that `close()` unblocks via abort.
        func readReport() -> [UInt8]? {
            var count = 0
            do {
                try inPipe.__sendIORequest(with: readBuffer, bytesTransferred: &count, completionTimeout: 0)
            } catch {
                return nil
            }
            return [UInt8](UnsafeRawBufferPointer(start: readBuffer.bytes, count: count))
        }

        func sendOutput(_ bytes: [UInt8]) {
            guard let outPipe, let buffer = try? interface.ioData(withCapacity: bytes.count) else { return }
            buffer.replaceBytes(in: NSRange(location: 0, length: bytes.count), withBytes: bytes)
            var sent = 0
            try? outPipe.__sendIORequest(with: buffer, bytesTransferred: &sent, completionTimeout: 0)
        }

        func close() {
            try? inPipe.__abort(with: .synchronous)
            interface.destroy()
        }
    }
}
