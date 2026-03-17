import Foundation
import IOKit.hid
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
final class DualSenseBatteryMonitor: @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.gsecontroller",
        category: "DualSenseBattery"
    )

    private static let sonyVendorID: Int = 0x054C
    private static let productIDs: Set<Int> = [0x0CE6, 0x0DF2] // DualSense, DualSense Edge

    private static let usbReportID: UInt32 = 0x01
    private static let btReportID:  UInt32 = 0x31
    private static let usbStatusOffset = 53
    private static let btStatusOffset  = 54

    /// Called on the main queue when battery data is parsed. (level: 0.0–1.0, isCharging)
    var onUpdate: ((Float, Bool) -> Void)?

    private var manager: IOHIDManager?
    // Heap-allocated so the pointer stays stable across C callback registrations.
    private let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    private var lastParsed = Date.distantPast

    deinit {
        stop()
        buf.deallocate()
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
            if mon.isDualSense(device) { mon.attach(device) }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func stop() {
        guard let m = manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = nil
    }

    private func isDualSense(_ device: IOHIDDevice) -> Bool {
        guard let pid = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
        else { return false }
        return Self.productIDs.contains(pid)
    }

    private func attach(_ device: IOHIDDevice) {
        IOHIDDeviceRegisterInputReportCallback(
            device, buf, 256,
            { ctx, _, _, _, reportID, data, length in
                guard let ctx else { return }
                Unmanaged<DualSenseBatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
                    .handle(reportID: reportID, data: data, length: length)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        Self.logger.info("Registered HID battery callback for DualSense")

        // Try an immediate property read — works even if gamecontrollerd has
        // seized the device and we never receive input report callbacks.
        pollDeviceProperty(device)
    }

    // MARK: - Device property polling (fallback when input reports are seized)

    /// Reads battery level via IOKit property, then direct Get_Report for the full BT
    /// input report (0x31). gamecontrollerd may seize the HID device exclusively, so
    /// input report callbacks only receive the 10-byte short report (0x01) with no
    /// battery data. IOHIDDeviceGetReport pulls the full 78-byte 0x31 report directly.
    func pollDeviceProperty(_ device: IOHIDDevice? = nil) {
        guard let dev = device ?? currentDevice else { return }

        // Try the standard Bluetooth HID driver battery property (integer 0–100).
        if let raw = IOHIDDeviceGetProperty(dev, "BatteryLevel" as CFString) as? NSNumber {
            let pct = raw.floatValue / 100.0
            Self.logger.debug("DualSense battery (property): \(raw.intValue)%")
            if pct > 0 {
                DispatchQueue.main.async { self.onUpdate?(pct, false) }
                return
            }
        }

        // The DualSense pushes a 10-byte short BT report (0x01) by default — no battery.
        // Synchronously request the full 78-byte BT report (0x31) which does contain it.
        var reportLen: CFIndex = 256
        if IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, CFIndex(Self.btReportID), buf, &reportLen) == kIOReturnSuccess,
           reportLen > Self.btStatusOffset {
            let byte = buf[Self.btStatusOffset]
            let level = Int(byte & 0x0F)
            let chargingNibble = Int((byte >> 4) & 0x0F)
            if level > 0, level <= 10 {
                let pct = Float(min(level * 10 + 5, 100)) / 100.0
                let charging = chargingNibble == 1 || chargingNibble == 2
                Self.logger.info("DualSense battery (GetReport 0x31): \(Int(pct * 100))% charging=\(charging)")
                DispatchQueue.main.async { self.onUpdate?(pct, charging) }
                return
            }
        }

        // Fallback: USB report 0x01 (covers wired connection).
        reportLen = 256
        if IOHIDDeviceGetReport(dev, kIOHIDReportTypeInput, CFIndex(Self.usbReportID), buf, &reportLen) == kIOReturnSuccess,
           reportLen > Self.usbStatusOffset {
            let byte = buf[Self.usbStatusOffset]
            let level = Int(byte & 0x0F)
            let chargingNibble = Int((byte >> 4) & 0x0F)
            if level > 0, level <= 10 {
                let pct = Float(min(level * 10 + 5, 100)) / 100.0
                let charging = chargingNibble == 1 || chargingNibble == 2
                Self.logger.info("DualSense battery (GetReport 0x01): \(Int(pct * 100))% charging=\(charging)")
                DispatchQueue.main.async { self.onUpdate?(pct, charging) }
                return
            }
        }
    }

    private var currentDevice: IOHIDDevice? {
        guard let m = manager,
              let devices = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>
        else { return nil }
        return devices.first(where: isDualSense)
    }

    private func handle(reportID: UInt32, data: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        // Rate-limit: parse at most once every 5 seconds.
        let now = Date()
        guard now.timeIntervalSince(lastParsed) >= 5 else { return }
        lastParsed = now

        let offset: Int
        switch reportID {
        case Self.usbReportID: offset = Self.usbStatusOffset
        case Self.btReportID:  offset = Self.btStatusOffset
        default: return
        }
        guard length > offset else { return }

        let byte = data[offset]
        let level = Int(byte & 0x0F)
        let chargingNibble = Int((byte >> 4) & 0x0F)
        guard level > 0, level <= 10 else { return }

        let pct    = Float(min(level * 10 + 5, 100)) / 100.0
        let charging = chargingNibble == 1 || chargingNibble == 2
        Self.logger.info("DualSense battery (report): \(Int(pct * 100))% charging=\(charging)")

        // Callbacks fire on the main run loop; defer one iteration to stay
        // outside any in-progress SwiftUI render pass.
        DispatchQueue.main.async { self.onUpdate?(pct, charging) }
    }
}
