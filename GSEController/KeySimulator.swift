import Foundation
import CoreGraphics
@preconcurrency import ApplicationServices
import AppKit
import os

enum KeySimulator {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.example.gsecontroller"
    private static let logger = Logger(subsystem: bundleID, category: "KeySimulator")

    // Called on a background queue when a FIFO write fails and reconnect begins.
    nonisolated(unsafe) static var onFIFOFailure: (() -> Void)?
    // Called on a background queue when the FIFO reconnects successfully.
    nonisolated(unsafe) static var onFIFORecovered: (() -> Void)?

    // All access to the FIFO write fd is serialized through this lock.
    private static let _fd = OSAllocatedUnfairLock<Int32>(initialState: -1)
    private enum HelperState {
        case idle
        case settingUp
        case ready
        case failed
    }
    // State and pending callbacks share one lock so ensureHelper's "check state + register
    // callback" and completeSetup's "update state + drain callbacks" are each one atomic op.
    // Using separate locks caused a race where completeSetup could drain an empty callback
    // list just before a late caller appended its callback, leaving it orphaned forever.
    private struct HelperSetup {
        var state: HelperState = .idle
        var pendingCallbacks: [(@MainActor (Bool) -> Void)] = []
    }
    private static let _setup = OSAllocatedUnfairLock<HelperSetup>(initialState: HelperSetup())
    // Serial queue for isHelperAccessibilityEnabled — prevents two concurrent FIFO readers
    // from racing over the single-byte AX response the helper writes.
    private static let axQueryQueue = DispatchQueue(label: "\(bundleID).ax-query")
    private static let fifoPath: String = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(bundleID).keys")
            .path
    }()

    private static let responseFifoPath: String = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(bundleID).ax-response")
            .path
    }()
    private static let agentLabel = "\(bundleID).helper"

    // Bump this when the helper source changes to force recompilation.
    private static let helperVersion = "v8-ax-fifo"

    private static var supportDir: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GSEController")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var helperURL: URL { supportDir.appendingPathComponent("keyhelper") }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    private static var helperLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GSEController/helper.log")
    }

    static var diagnostics: KeyHelperDiagnostics {
        KeyHelperDiagnostics(
            helperPath: helperURL.path,
            launchAgentPath: plistURL.path,
            launchAgentLabel: agentLabel,
            fifoPath: fifoPath,
            responseFifoPath: responseFifoPath,
            logPath: helperLogURL.path,
            helperExists: FileManager.default.fileExists(atPath: helperURL.path),
            launchAgentExists: FileManager.default.fileExists(atPath: plistURL.path),
            fifoExists: FileManager.default.fileExists(atPath: fifoPath),
            responseFifoExists: FileManager.default.fileExists(atPath: responseFifoPath)
        )
    }

    // 4-byte protocol:
    //   buf[0]: command type
    //     0 = press+release key
    //     1 = press-only key
    //     2 = release-only key
    //     3 = AX status query (helper writes 1 byte to RESPONSE_FIFO_PATH: 0x01=trusted, 0x00=not)
    //   buf[1..2]: uint16 keyCode (little-endian, unused for type 3)
    //   buf[3]: reserved (0)
    private static let helperSource = """
        #include <CoreGraphics/CoreGraphics.h>
        #include <ApplicationServices/ApplicationServices.h>
        #include <fcntl.h>
        #include <unistd.h>
        #include <stdint.h>
        #include <string.h>
        #include <stdlib.h>
        static const char *get_fifo_path(void) {
            const char *env = getenv("FIFO_PATH");
            if (!env) {
                const char msg[] = "FIFO_PATH not set\\n";
                write(2, msg, sizeof(msg) - 1);
                exit(1);
            }
            return env;
        }
        int main(int argc, char *argv[]) {
            if (argc > 1 && strcmp(argv[1], "--check-ax") == 0)
                return AXIsProcessTrusted() ? 0 : 1;
            const char *fifo_path = get_fifo_path();
            const char *resp_path = getenv("RESPONSE_FIFO_PATH");
            while (1) {
                int fd = open(fifo_path, O_RDONLY);
                if (fd < 0) { sleep(1); continue; }
                uint8_t buf[4];
                while (read(fd, buf, 4) == 4) {
                    uint8_t  type    = buf[0];
                    uint16_t keyCode = (uint16_t)buf[1] | ((uint16_t)buf[2] << 8);
                    if (type == 3) {
                        // AX status query: write 1 (trusted) or 0 (not trusted) to response FIFO.
                        // This helper runs under launchd so AXIsProcessTrusted() reflects the
                        // helper's own TCC grant, not the parent app's.
                        if (resp_path) {
                            int rfd = open(resp_path, O_WRONLY | O_NONBLOCK);
                            if (rfd >= 0) {
                                uint8_t trusted = AXIsProcessTrusted() ? 1 : 0;
                                write(rfd, &trusted, 1);
                                close(rfd);
                            }
                        }
                        continue;
                    }
                    if (type == 0 || type == 1) {
                        CGEventRef down = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)keyCode, true);
                        if (down) { CGEventPost(kCGHIDEventTap, down); CFRelease(down); }
                    }
                    if (type == 0 || type == 2) {
                        CGEventRef up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)keyCode, false);
                        if (up) { CGEventPost(kCGHIDEventTap, up); CFRelease(up); }
                    }
                }
                close(fd);
            }
            return 0;
        }
        """

    // MARK: - Lifecycle

    static func ensureHelper(onComplete: (@MainActor (Bool) -> Void)? = nil) {
        let (shouldSetup, immediateResult) = _setup.withLock { setup -> (Bool, Bool?) in
            switch setup.state {
            case .ready:
                return (false, true)
            case .idle, .failed:
                setup.state = .settingUp
                if let cb = onComplete { setup.pendingCallbacks.append(cb) }
                return (true, nil)
            case .settingUp:
                if let cb = onComplete { setup.pendingCallbacks.append(cb) }
                return (false, nil)
            }
        }
        if let result = immediateResult, let onComplete {
            Task { @MainActor in onComplete(result) }
        }
        guard shouldSetup else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let recompiled = ensureBinary()
            guard FileManager.default.fileExists(atPath: helperURL.path) else {
                logger.error("ensureHelper: binary missing after compile attempt, aborting")
                completeSetup(success: false)
                return
            }
            ensureFIFO()
            ensureResponseFIFO()
            // Always restart the agent when the binary was recompiled so the launchd
            // plist picks up any new env vars (e.g. RESPONSE_FIFO_PATH).
            if recompiled || !isAgentRunning() {
                ensureLaunchdAgent()
            }
            openFIFO()
        }
    }

    static func stopHelper() {
        _fd.withLock { fd in
            guard fd >= 0 else { return }
            Darwin.close(fd)
            fd = -1
            logger.info("FIFO write end closed")
        }
        _setup.withLock { $0.state = .idle }
    }

    // MARK: - Key posting

    /// Press and release a key (type 0).
    static func pressKey(_ keyCode: UInt16) {
        writeCommand(type: 0, keyCode: keyCode)
    }

    /// Send a modifier key down event (type 1). No-op for `.none`.
    static func modifierDown(_ modifier: KeyModifier) {
        guard modifier != .none else { return }
        writeCommand(type: 1, keyCode: modifier.keyCode)
    }

    /// Send a modifier key up event (type 2). No-op for `.none`.
    static func modifierUp(_ modifier: KeyModifier) {
        guard modifier != .none else { return }
        writeCommand(type: 2, keyCode: modifier.keyCode)
    }

    static func encodeCommand(type commandType: UInt8, keyCode: UInt16) -> [UInt8] {
        [commandType, UInt8(keyCode & 0xFF), UInt8(keyCode >> 8), 0]
    }

    private static func writeCommand(type: UInt8, keyCode: UInt16) {
        _fd.withLock { fd in
            guard fd >= 0 else {
                logger.warning("writeCommand: helper not ready yet")
                return
            }
            let buf = encodeCommand(type: type, keyCode: keyCode)
            let n = buf.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, 4) }
            if n != 4 {
                logger.warning("FIFO write failed (errno \(errno)), reopening")
                Darwin.close(fd)
                fd = -1
                onFIFOFailure?()
                DispatchQueue.global(qos: .userInitiated).async { openFIFO() }
            }
        }
    }

    // MARK: - Accessibility

    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var isHelperAccessibilityEnabled: Bool {
        // Serialise on axQueryQueue: the helper writes exactly one response byte per query,
        // so two concurrent callers would race over that byte and one would time out.
        axQueryQueue.sync {
            guard FileManager.default.fileExists(atPath: helperURL.path) else { return false }
            // Query the already-running launchd helper via the key FIFO (command type 3).
            // The helper is bootstrapped by launchd, making it its own TCC responsible process,
            // so AXIsProcessTrusted() inside it correctly reflects the helper's own grant —
            // independent of whether the parent app is trusted yet.
            ensureResponseFIFO()
            // Open the response FIFO for reading before sending the query so the helper
            // can open it for writing without receiving ENXIO.
            let rfd = Darwin.open(responseFifoPath, O_RDONLY | O_NONBLOCK)
            guard rfd >= 0 else { return false }
            defer { Darwin.close(rfd) }
            // Send type-3 command. Returns false immediately if the helper isn't running yet.
            let sent = _fd.withLock { fd -> Bool in
                guard fd >= 0 else { return false }
                var cmd: (UInt8, UInt8, UInt8, UInt8) = (3, 0, 0, 0)
                return withUnsafeBytes(of: &cmd) { Darwin.write(fd, $0.baseAddress!, 4) } == 4
            }
            guard sent else { return false }
            // Poll for the 1-byte response with a 2-second timeout (20 × 100 ms).
            var response: UInt8 = 0
            for _ in 0..<20 {
                let n = Darwin.read(rfd, &response, 1)
                if n == 1 { return response == 1 }
                usleep(100_000)
            }
            return false
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func revealHelperInFinder() {
        NSWorkspace.shared.selectFile(helperURL.path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Private setup

    @discardableResult
    private static func ensureBinary() -> Bool {
        let versionURL = supportDir.appendingPathComponent("keyhelper.version")
        if let stored = try? String(contentsOf: versionURL, encoding: .utf8),
           stored == helperVersion,
           FileManager.default.fileExists(atPath: helperURL.path) {
            logger.info("Key helper binary up to date")
            return false
        }

        logger.info("Compiling key helper...")
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("gse_keyhelper.c")
        do {
            try helperSource.write(to: src, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write source: \(error.localizedDescription, privacy: .public)")
            return false
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        proc.arguments = [src.path, "-o", helperURL.path,
                          "-framework", "CoreGraphics",
                          "-framework", "ApplicationServices"]
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            logger.error("cc launch failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        if proc.terminationStatus == 0 {
            // Ad-hoc sign so the binary has a stable identity for Accessibility trust.
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--sign", "-", "--force", helperURL.path]
            sign.standardOutput = FileHandle.nullDevice
            sign.standardError = FileHandle.nullDevice
            try? sign.run()
            sign.waitUntilExit()
            if sign.terminationStatus == 0 {
                try? helperVersion.write(to: versionURL, atomically: true, encoding: .utf8)
                logger.info("Compiled and signed key helper at \(helperURL.path, privacy: .public)")
            } else {
                // Signing failed — binary was compiled but is unsigned. Skip version file
                // so the next launch recompiles. Still return true so the caller restarts
                // the launchd agent to pick up the new binary.
                logger.warning("codesign ad-hoc sign failed — skipping version file to force recompile next launch")
            }
            return true
        } else {
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            logger.error("cc failed: \(errStr, privacy: .public)")
        }
        return false
    }

    private static func ensureFIFO() {
        var st = stat()
        if lstat(fifoPath, &st) == 0 {
            if (st.st_mode & S_IFMT) == S_IFIFO { return }
            // Not a FIFO — remove and recreate
            Darwin.unlink(fifoPath)
        }
        if Darwin.mkfifo(fifoPath, 0o600) != 0 {
            logger.error("mkfifo failed (errno \(errno))")
        } else {
            logger.info("Created FIFO at \(fifoPath, privacy: .public)")
        }
    }

    private static func ensureResponseFIFO() {
        var st = stat()
        if lstat(responseFifoPath, &st) == 0 {
            if (st.st_mode & S_IFMT) == S_IFIFO { return }
            Darwin.unlink(responseFifoPath)
        }
        if Darwin.mkfifo(responseFifoPath, 0o600) != 0 {
            logger.error("mkfifo response FIFO failed (errno \(errno))")
        }
    }

    private static func isAgentRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "gui/\(getuid())/\(agentLabel)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            logger.error("launchctl spawn failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static func ensureLaunchdAgent() {
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            logger.error("Helper binary missing, skipping launchd setup")
            return
        }

        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GSEController")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(agentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(helperURL.path)</string>
                </array>
                <key>EnvironmentVariables</key>
                <dict>
                    <key>FIFO_PATH</key>
                    <string>\(fifoPath)</string>
                    <key>RESPONSE_FIFO_PATH</key>
                    <string>\(responseFifoPath)</string>
                </dict>
                <key>KeepAlive</key>
                <true/>
                <key>StandardErrorPath</key>
                    <string>\(helperLogURL.path)</string>
            </dict>
            </plist>
            """

        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write plist: \(error.localizedDescription, privacy: .public)")
            return
        }

        let uid = getuid()
        _ = launchctl(["bootout", "gui/\(uid)/\(agentLabel)"])
        let status = launchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        if status == 0 {
            logger.info("launchd agent bootstrapped (uid=\(uid))")
        } else {
            logger.error("launchctl bootstrap failed (status \(status))")
        }
    }

    private static func openFIFO(attempt: Int = 0) {
        // O_NONBLOCK prevents the open from blocking indefinitely when the helper
        // hasn't opened its read end yet. On ENXIO we retry up to 20 times (10s total).
        let fd = Darwin.open(fifoPath, O_WRONLY | O_NONBLOCK)
        if fd < 0 {
            if errno == ENXIO && attempt < 20 {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
                    openFIFO(attempt: attempt + 1)
                }
            } else {
                logger.error("open FIFO failed after \(attempt) retries (errno \(errno))")
                completeSetup(success: false)
            }
            return
        }
        _fd.withLock { current in
            if current >= 0 {
                // Another call already opened — close the duplicate.
                Darwin.close(fd)
            } else {
                current = fd
                logger.info("FIFO open for writing (fd=\(fd))")
                onFIFORecovered?()
            }
        }
        completeSetup(success: true)
    }

    private static func completeSetup(success: Bool) {
        let callbacks = _setup.withLock { setup -> [(@MainActor (Bool) -> Void)] in
            setup.state = success ? .ready : .failed
            defer { setup.pendingCallbacks.removeAll() }
            return setup.pendingCallbacks
        }
        for callback in callbacks {
            Task { @MainActor in callback(success) }
        }
    }
}
