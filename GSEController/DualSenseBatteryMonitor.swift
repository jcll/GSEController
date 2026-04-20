import Foundation
import IOKit.hid
import QuartzCore
import os

/// Reads DualSense battery level directly from raw HID input reports.
///
/// GCDeviceBattery returns level=0 / state=.unknown for DualSense on macOS —
/// the GameController framework creates the battery object but never parses
/// the status nibble from the HID report stream.
///
/// We open the device concurrently (non-exclusively via kIOHIDOptionsTypeNone)
/// alongside the GameController framework and parse the status byte ourselves.
///
/// Report structure (from Linux hid-playstation.c):
///   Status byte = dualsense_input_report.status[0]
///   Lower nibble (bits 0–3): battery level 0–10  → percentage = min(level × 10 + 5, 100)
///   Upper nibble (bits 4–7): charging state       0=discharging, 1=charging, 2=full
///
/// Byte offset within the IOHIDDevice report buffer (report ID stripped by macOS):
///   USB  (report ID 0x01): data[53]   — struct starts at data[0]
///   BT   (report ID 0x31): data[54]   — 1 BT header byte precedes the common struct
@MainActor
final class DualSenseBatteryMonitor {
    // This monitor is deliberately narrow: it supplements GameController's
    // broken DualSense battery reporting without becoming the source of truth
    // for controller attachment or input handling.
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gsecontroller",
        category: "DualSenseBattery"
    )

    private nonisolated static let sonyVendorID: Int = 0x054C
    private nonisolated static let productIDs: Set<Int> = [0x0CE6, 0x0DF2] // DualSense, DualSense Edge

    private nonisolated static let usbReportID: UInt32 = 0x01
    private nonisolated static let btReportID:  UInt32 = 0x31
    private nonisolated static let usbStatusOffset = 53
    private nonisolated static let btStatusOffset  = 54
    private struct SendableDevice: @unchecked Sendable {
        let value: IOHIDDevice
    }

    /// Called on the main queue when battery data is parsed. (level: 0.0–1.0, isCharging)
    var onUpdate: ((Float, Bool) -> Void)?

    private var manager: IOHIDManager?
    // Per-device heap buffers for IOHIDDeviceRegisterInputReportCallback.
    // Each attached device gets its own buffer so concurrent HID reports from
    // multiple DualSense controllers don't race on a shared pointer.
    // Allocated in attach(_:), freed in stop().
    private var callbackBuffers: [UnsafeMutablePointer<UInt8>] = []
    // Tracks attached devices by CF object identity to prevent double-registration.
    private var knownDevices: [IOHIDDevice] = []
    // Cached reference for the no-arg pollDeviceProperty() overload.
    private var lastAttachedDevice: IOHIDDevice?
    private var lastParsed: Double = 0

    deinit {
        // ControllerManager is @MainActor and owns this object, so deinit runs on main.
        MainActor.assumeIsolated { stop() }
    }

    func start() {
        guard manager == nil else { return }

        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDVendorIDKey as String: Self.sonyVendorID] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        guard IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            Self.logger.error("IOHIDManager open failed")
            return
        }
        manager = m

        // Attach to any DualSense already connected.
        if let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> {
            for device in devices where isDualSense(device) { attach(device) }
        }

        // Watch for future connections.
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, device in
            guard let ctx else { return }
            let mon = Unmanaged<DualSenseBatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            // Callback fires on the main run loop — safe to assume main actor isolation.
            MainActor.assumeIsolated {
                if mon.isDualSense(device) { mon.attach(device) }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func stop() {
        guard let m = manager else { return }
        // Deregister per-device input callbacks BEFORE closing the manager.
        // After IOHIDManagerClose, device references may be invalid; touching
        // them is undefined behavior. The dummy buffer below is only a placeholder
        // for the callback signature — the actual original buffers are freed after.
        var dummyBuf: UInt8 = 0
        for device in knownDevices {
            IOHIDDeviceRegisterInputReportCallback(device, &dummyBuf, 1, nil, nil)
        }
        // Clear the matching callback before unscheduling so no queued CFRunLoop event
        // can fire it with a dangling unretained self pointer after deallocation.
        IOHIDManagerRegisterDeviceMatchingCallback(m, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
        for b in callbackBuffers { b.deallocate() }
        callbackBuffers.removeAll()
        knownDevices.removeAll()
        lastAttachedDevice = nil
    }

    private func isDualSense(_ device: IOHIDDevice) -> Bool {
        guard let pid = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
        else { return false }
        return Self.productIDs.contains(pid)
    }

    // MARK: - Battery byte parsing

    /// Parses the DualSense status byte: lower nibble = level (1–10), upper nibble = charging state.
    /// Returns nil when level == 0 (controller reports no data) or level > 10 (malformed).
    nonisolated static func parseBatteryByte(_ byte: UInt8) -> (level: Float, charging: Bool)? {
        let level = Int(byte & 0x0F)
        let chargingNibble = Int((byte >> 4) & 0x0F)
        guard level > 0, level <= 10 else { return nil }
        return (Float(min(level * 10 + 5, 100)) / 100.0, chargingNibble == 1 || chargingNibble == 2)
    }

    private func attach(_ device: IOHIDDevice) {
        // Guard against double-registration when the matching callback fires
        // for devices that were already picked up by the CopyDevices loop.
        guard !knownDevices.contains(where: { CFEqual($0, device) }) else { return }
        knownDevices.append(device)
        lastAttachedDevice = device

        let devBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        callbackBuffers.append(devBuf)
        IOHIDDeviceRegisterInputReportCallback(
            device, devBuf, 256,
            { ctx, _, _, _, reportID, data, length in
                guard let ctx else { return }
                let mon = Unmanaged<DualSenseBatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
                // Callback fires on the main run loop — safe to assume main actor isolation.
                // assumeIsolated is synchronous so the data pointer remains valid throughout.
                MainActor.assumeIsolated {
                    mon.handle(reportID: reportID, data: data, length: length)
                }
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        Self.logger.info("Registered HID battery callback for DualSense")

        // Try an immediate property read — works even if gamecontrollerd has
        // seized the device and we never receive input report callbacks.
        // Use the async path to avoid blocking the main thread with HID I/O.
        pollDevicePropertyAsync(device)
    }

    // MARK: - Device property polling (fallback when input reports are seized)

    /// Reads battery level via IOKit property, then direct Get_Report for the full BT
    /// input report (0x31). gamecontrollerd may seize the HID device exclusively, so
    /// input report callbacks only receive the 10-byte short report (0x01) with no
    /// battery data. IOHIDDeviceGetReport pulls the full 78-byte 0x31 report directly.
    func pollDeviceProperty(_ device: IOHIDDevice? = nil) {
        guard let dev = device ?? lastAttachedDevice else { return }
        if let reading = Self.readBattery(dev) {
            onUpdate?(reading.level, reading.charging)
        }
    }

    func pollDevicePropertyAsync(_ device: IOHIDDevice? = nil) {
        guard let dev = device ?? lastAttachedDevice else { return }
        let sendableDevice = SendableDevice(value: dev)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let reading = Self.readBattery(sendableDevice.value) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.onUpdate?(reading.level, reading.charging)
            }
        }
    }

    private nonisolated static func readBattery(_ dev: IOHIDDevice) -> (level: Float, charging: Bool)? {
        var propertyPct: Float? = nil
        if let raw = IOHIDDeviceGetProperty(dev, "BatteryLevel" as CFString) as? NSNumber {
            let pct = raw.floatValue / 100.0
            if pct > 0 {
                Self.logger.debug("DualSense battery (property): \(raw.intValue)%")
                propertyPct = pct
            }
        }

        // Local buffer — avoids any reentrancy hazard if IOHIDDeviceGetReport
        // pumps the main run loop before returning.
        var buf = [UInt8](repeating: 0, count: 256)

        // The DualSense pushes a 10-byte short BT report (0x01) by default — no battery.
        // Synchronously request the full 78-byte BT report (0x31) which does contain it.
        var reportLen: CFIndex = 256
        let btResult = buf.withUnsafeMutableBufferPointer { ptr in
            IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, CFIndex(Self.btReportID), ptr.baseAddress!, &reportLen)
        }
        if btResult == kIOReturnSuccess, reportLen > Self.btStatusOffset,
           let (pct, charging) = Self.parseBatteryByte(buf[Self.btStatusOffset]) {
            Self.logger.info("DualSense battery (GetReport 0x31): \(Int(pct * 100))% charging=\(charging)")
            return (pct, charging)
        }

        // Fallback: USB report 0x01 (covers wired connection).
        reportLen = 256
        let usbResult = buf.withUnsafeMutableBufferPointer { ptr in
            IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, CFIndex(Self.usbReportID), ptr.baseAddress!, &reportLen)
        }
        if usbResult == kIOReturnSuccess, reportLen > Self.usbStatusOffset,
           let (pct, charging) = Self.parseBatteryByte(buf[Self.usbStatusOffset]) {
            Self.logger.info("DualSense battery (GetReport 0x01): \(Int(pct * 100))% charging=\(charging)")
            return (pct, charging)
        }

        // Both report paths failed — fall back to property level with charging state unknown.
        if let pct = propertyPct {
            return (pct, false)
        }
        return nil
    }

    private func handle(reportID: UInt32, data: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        // Rate-limit: parse at most once every 5 seconds. Use CACurrentMediaTime()
        // instead of Date() so NTP adjustments don't break throttling.
        let now = CACurrentMediaTime()
        guard now - lastParsed >= 5 else { return }

        let offset: Int
        switch reportID {
        case Self.usbReportID: offset = Self.usbStatusOffset
        case Self.btReportID:  offset = Self.btStatusOffset
        default: return
        }
        guard length > offset else { return }

        guard let (pct, charging) = Self.parseBatteryByte(data[offset]) else { return }
        lastParsed = now
        let onUpdate = self.onUpdate
        Self.logger.info("DualSense battery (report): \(Int(pct * 100))% charging=\(charging)")

        // Defer one iteration to stay outside any in-progress SwiftUI render pass.
        DispatchQueue.main.async {
            onUpdate?(pct, charging)
        }
    }
}
