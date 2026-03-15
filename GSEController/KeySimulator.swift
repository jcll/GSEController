import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import os

enum KeySimulator {
    private static let logger = Logger(subsystem: "com.jcll.gsecontroller", category: "KeySimulator")
    private static let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

    // All access to the FIFO write fd is serialized through this lock.
    private static let _fd = OSAllocatedUnfairLock<Int32>(initialState: -1)
    private static let _setupStarted = OSAllocatedUnfairLock<Bool>(initialState: false)
    private static let fifoPath: String = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("com.jcll.gsecontroller.keys")
            .path
    }()
    private static let agentLabel = "com.jcll.gsecontroller.helper"

    // Bump this when the helper source changes to force recompilation.
    private static let helperVersion = "v7-tmpdir"

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

    // 4-byte protocol:
    //   buf[0]: command type — 0=press+release, 1=press-only, 2=release-only
    //   buf[1..2]: uint16 keyCode (little-endian)
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
            return env ? env : "/tmp/com.jcll.gsecontroller.keys";
        }
        int main(int argc, char *argv[]) {
            if (argc > 1 && strcmp(argv[1], "--check-ax") == 0)
                return AXIsProcessTrusted() ? 0 : 1;
            const char *fifo_path = get_fifo_path();
            while (1) {
                int fd = open(fifo_path, O_RDONLY);
                if (fd < 0) { sleep(1); continue; }
                uint8_t buf[4];
                while (read(fd, buf, 4) == 4) {
                    uint8_t  type    = buf[0];
                    uint16_t keyCode = (uint16_t)buf[1] | ((uint16_t)buf[2] << 8);
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

    static func ensureHelper() {
        let shouldSetup = _setupStarted.withLock { started -> Bool in
            if started { return false }
            started = true
            return true
        }
        guard shouldSetup else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            ensureBinary()
            guard FileManager.default.fileExists(atPath: helperURL.path) else {
                logger.error("ensureHelper: binary missing after compile attempt, aborting")
                _setupStarted.withLock { $0 = false }
                return
            }
            ensureFIFO()
            if !isAgentRunning() {
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
        _setupStarted.withLock { $0 = false }
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

    private static func writeCommand(type: UInt8, keyCode: UInt16) {
        _fd.withLock { fd in
            guard fd >= 0 else {
                logger.warning("writeCommand: helper not ready yet")
                return
            }
            var buf: (UInt8, UInt8, UInt8, UInt8) = (
                type,
                UInt8(keyCode & 0xFF),
                UInt8(keyCode >> 8),
                0
            )
            let n = Darwin.write(fd, &buf, 4)
            if n != 4 {
                logger.warning("FIFO write failed (errno \(errno)), reopening")
                Darwin.close(fd)
                fd = -1
                DispatchQueue.global(qos: .userInitiated).async { openFIFO() }
            }
        }
    }

    // MARK: - Accessibility

    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibility() {
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var isHelperAccessibilityEnabled: Bool {
        guard FileManager.default.fileExists(atPath: helperURL.path) else { return false }
        let proc = Process()
        proc.executableURL = helperURL
        proc.arguments = ["--check-ax"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
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

    private static func ensureBinary() {
        let versionURL = supportDir.appendingPathComponent("keyhelper.version")
        if let stored = try? String(contentsOf: versionURL, encoding: .utf8),
           stored == helperVersion,
           FileManager.default.fileExists(atPath: helperURL.path) {
            logger.info("Key helper binary up to date")
            return
        }

        logger.info("Compiling key helper...")
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("gse_keyhelper.c")
        do {
            try helperSource.write(to: src, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write source: \(error.localizedDescription, privacy: .public)")
            return
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
            return
        }

        if proc.terminationStatus == 0 {
            try? helperVersion.write(to: versionURL, atomically: true, encoding: .utf8)
            logger.info("Compiled key helper at \(helperURL.path, privacy: .public)")
        } else {
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            logger.error("cc failed: \(errStr, privacy: .public)")
        }
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

    private static func isAgentRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "gui/\(getuid())/\(agentLabel)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
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
                </dict>
                <key>KeepAlive</key>
                <true/>
                <key>StandardErrorPath</key>
                <string>\(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/GSEController/helper.log").path)</string>
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

    private static func openFIFO() {
        // O_WRONLY blocks until the helper opens its read end — which happens
        // shortly after launchd starts the process above.
        let fd = Darwin.open(fifoPath, O_WRONLY)
        if fd < 0 {
            logger.error("open FIFO failed (errno \(errno))")
            return
        }
        _fd.withLock { current in
            if current >= 0 {
                // Another call already opened — close the duplicate.
                Darwin.close(fd)
            } else {
                current = fd
                logger.info("FIFO open for writing (fd=\(fd))")
            }
        }
    }
}
