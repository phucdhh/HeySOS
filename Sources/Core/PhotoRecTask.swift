// PhotoRecTask.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

// MARK: - ScanOptions

/// User-visible options that control how PhotoRec scans the disk.
struct ScanOptions: Equatable {
    /// When true, scan the whole partition (not just unallocated/free clusters).
    var scanWholePartition: Bool = false
    /// File type extensions to recover. Empty = recover all types.
    var fileTypeFilter: Set<String> = []
}

/// Wraps the PhotoRec binary, running it with administrator privileges via
/// `osascript do shell script … with administrator privileges`.
///
/// ## Why administrator privileges?
/// Reading raw block devices (e.g. /dev/disk9) on macOS requires root.
/// Full Disk Access (TCC) is file-level only; raw device access is kernel-level.
///
/// ## Architecture
/// 1. An Expect script is written to a temp .exp file.  It spawns photorec and
///    navigates its ncurses TUI automatically (Proceed → Search → Other → Confirm).
/// 2. The Expect script uses `log_file` to copy all photorec output to a temp log.
/// 3. A DispatchSourceTimer polls the temp log every 200 ms, streaming new bytes
///    to the caller via AsyncStream<RecoveryEvent>.
/// 4. The actual photorec exit code is captured via a sentinel line
///    `__HEYSOS_EXIT__:N` written by the Expect script after photorec exits.
/// 5. On cancel, photorec is terminated via a privileged pkill.
///
/// ## Why Expect?
/// PhotoRec's batch `/cmd` mode is compiled only for Windows (`#ifdef __MINGW32__`).
/// On macOS/Unix, photorec has no non-interactive mode — the ncurses TUI must be
/// driven by a pseudo-TTY.  `/usr/bin/expect` is pre-installed on macOS and provides
/// exactly that.
actor PhotoRecTask {

    // MARK: - State

    private var osascriptProc: Process?
    private var continuation: AsyncStream<RecoveryEvent>.Continuation?
    private var pollingSource: DispatchSourceTimer?
    private var logHandle: FileHandle?
    private var logPath: String?
    private var expPath: String?  // temp Expect script

    // Actor-isolated parse state — avoids Swift 6 data race on captured vars
    private var parseResult = PhotoRecLogParser.ParseResult()
    private var lastProgressYield = Date.distantPast
    private var permissionDenied = false

    // MARK: - Constants

    private let progressThrottleInterval: TimeInterval = 0.5
    private let exitSentinel = "__HEYSOS_EXIT__"

    // MARK: - Public API

    /// Launch PhotoRec with administrator privileges.
    ///
    /// macOS will display a native password dialog before photorec runs.
    ///
    /// - Parameters:
    ///   - device: The device to scan (read-only).
    ///   - outputDir: Directory where recovered files will be written.
    ///   - options: Scan options (coverage, file type filter).
    /// - Returns: An `AsyncStream<RecoveryEvent>` yielding progress and completion events.
    func start(
        device: StorageDevice,
        outputDir: URL,
        options: ScanOptions = ScanOptions()
    ) -> AsyncStream<RecoveryEvent> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            Task {
                await self.launch(device: device, outputDir: outputDir, options: options, continuation: continuation)
            }
        }
    }

    /// Cancel the running recovery.
    /// Sends SIGTERM to photorec via a privileged pkill, then cleans up.
    func cancel() {
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        kill.arguments = ["-e", "do shell script \"pkill -x photorec\" with administrator privileges"]
        kill.standardOutput = FileHandle.nullDevice
        kill.standardError  = FileHandle.nullDevice
        try? kill.run()

        osascriptProc?.terminate()
        tearDown()
        continuation?.yield(.cancelled)
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private — launch

    private func launch(
        device: StorageDevice,
        outputDir: URL,
        options: ScanOptions,
        continuation: AsyncStream<RecoveryEvent>.Continuation
    ) {
        self.continuation = continuation

        guard let binaryURL = resolveBinaryURL(name: "photorec") else {
            continuation.yield(.failed(error: .binaryNotFound("photorec")))
            continuation.finish()
            return
        }

        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            continuation.yield(.failed(error: .outputDirectoryNotWritable(outputDir)))
            continuation.finish()
            return
        }

        // ── Temp log file ────────────────────────────────────────────────────
        let uid   = UUID().uuidString
        let lp    = NSTemporaryDirectory() + "heysos_\(uid).log"
        let ep    = NSTemporaryDirectory() + "heysos_\(uid).exp"
        FileManager.default.createFile(atPath: lp, contents: nil)
        guard let lh = FileHandle(forReadingAtPath: lp) else {
            continuation.yield(.failed(error: .outputDirectoryNotWritable(outputDir)))
            continuation.finish()
            return
        }
        self.logPath = lp
        self.logHandle = lh
        self.expPath = ep

        // ── Write Expect script ───────────────────────────────────────────────
        let expectScript = makeExpectScript(
            binary:  binaryURL.path,
            outDir:  outputDir.path,
            device:  device.id,
            logPath: lp,
            sentinel: exitSentinel,
            options: options
        )
        guard (try? expectScript.write(toFile: ep, atomically: true, encoding: .utf8)) != nil,
              FileManager.default.fileExists(atPath: ep) else {
            continuation.yield(.failed(error: .outputDirectoryNotWritable(outputDir)))
            continuation.finish()
            return
        }

        // ── Build shell command ───────────────────────────────────────────────
        // Escape a string for embedding inside an AppleScript double-quoted string.
        let esc = { (s: String) -> String in
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }
        // Run: /usr/bin/expect /tmp/heysos_UUID.exp
        // The Expect script handles all TUI navigation and writes the log file itself.
        let shellCmd = "/usr/bin/expect \"\(esc(ep))\""
        let appleScript = "do shell script \"\(esc(shellCmd))\" with administrator privileges"

        // ── Emit display command (show the underlying photorec call) ──────────
        continuation.yield(.log("$ \(binaryURL.path) /d \(outputDir.path) \(device.id)\n"))

        // ── Start polling timer ───────────────────────────────────────────────
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            Task { await self?.pollLogFile(continuation: continuation) }
        }
        timer.resume()
        self.pollingSource = timer

        // ── Launch osascript ─────────────────────────────────────────────────
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments     = ["-e", appleScript]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        self.osascriptProc = proc

        proc.terminationHandler = { [weak self] _ in
            Task {
                // Allow the polling timer one final pass to flush remaining bytes.
                try? await Task.sleep(for: .milliseconds(400))
                await self?.finalizeScan(outputDir: outputDir, continuation: continuation)
            }
        }

        do {
            try proc.run()
        } catch {
            tearDown()
            continuation.yield(.failed(error: .binaryNotFound("photorec")))
            continuation.finish()
        }
    }

    // MARK: - Private — log polling

    private func pollLogFile(continuation: AsyncStream<RecoveryEvent>.Continuation) {
        guard let lh = logHandle else { return }
        let data = lh.readDataToEndOfFile()
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        processOutput(text, continuation: continuation)
    }

    /// Final flush after osascript exits: read remaining bytes, parse exit sentinel.
    private func finalizeScan(
        outputDir: URL,
        continuation: AsyncStream<RecoveryEvent>.Continuation
    ) {
        if let lh = logHandle {
            let data = lh.readDataToEndOfFile()
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                processOutput(text, continuation: continuation)
            }
        }

        // Recover the real photorec exit code from the sentinel line.
        let exitCode: Int32
        if let lp = logPath,
           let fullText = try? String(contentsOfFile: lp, encoding: .utf8),
           let sentinelLine = fullText.components(separatedBy: .newlines)
               .last(where: { $0.hasPrefix(exitSentinel + ":") }),
           let code = Int32(sentinelLine.dropFirst((exitSentinel + ":").count)) {
            exitCode = code
        } else {
            // No sentinel → osascript itself failed (user dismissed auth dialog, etc.)
            exitCode = -1
        }

        tearDown()
        handleTermination(exitCode, outputDir: outputDir, continuation: continuation)
    }

    // MARK: - Private — output processing

    private func processOutput(
        _ text: String,
        continuation: AsyncStream<RecoveryEvent>.Continuation
    ) {
        // Strip ANSI/VT100 sequences then filter sentinel lines, producing
        // clean human-readable console output.
        let clean = Self.stripANSI(text)
        let visibleLines = clean.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix(exitSentinel) }
            .map    { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Deduplicate consecutive identical lines (PhotoRec redraws status in-place).
        var deduped: [String] = []
        for line in visibleLines {
            if line != deduped.last { deduped.append(line) }
        }

        if !deduped.isEmpty {
            continuation.yield(.log(deduped.joined(separator: "\n") + "\n"))
        }

        // Detect permission errors from any output line.
        if clean.localizedCaseInsensitiveContains("Permission denied") ||
           clean.localizedCaseInsensitiveContains("Operation not permitted") ||
           clean.localizedCaseInsensitiveContains("Unable to open") {
            permissionDenied = true
        }

        // Parse the ANSI-stripped text so "Pass 1 - Reading sector…" lines match.
        for line in clean.components(separatedBy: .newlines) {
            PhotoRecLogParser.parseLine(line, into: &parseResult)
        }

        let now = Date()
        guard now.timeIntervalSince(lastProgressYield) >= progressThrottleInterval else { return }
        lastProgressYield = now

        continuation.yield(.progress(
            filesFound: parseResult.filesFound,
            speed: parseResult.elapsedSeconds > 0
                ? Self.formatSpeed(sectors: parseResult.currentSector,
                                   seconds: parseResult.elapsedSeconds)
                : "—",
            percent: parseResult.fraction.map { $0 * 100 } ?? 0,
            estimatedSeconds: parseResult.estimatedSeconds
        ))
    }

    private func handleTermination(
        _ exitCode: Int32,
        outputDir: URL,
        continuation: AsyncStream<RecoveryEvent>.Continuation
    ) {
        continuation.yield(.log("\n[photorec exited with code \(exitCode)]\n"))

        if exitCode == -1 {
            // User dismissed the macOS administrator password dialog.
            continuation.yield(.cancelled)
        } else if permissionDenied {
            continuation.yield(.failed(error: .insufficientPermissions))
        } else if exitCode == 0 || parseResult.isCompleted || parseResult.filesFound > 0 {
            // Treat any run that recovered files as a success, even if exit code
            // is non-zero (e.g. PhotoRec exits 1 after the session-save prompt).
            let total = parseResult.recoveredTypes.values.reduce(0, +)
            continuation.yield(.completed(totalFiles: max(total, parseResult.filesFound), outputDir: outputDir))
        } else if exitCode == 15 {
            continuation.yield(.cancelled)
        } else {
            continuation.yield(.failed(error: .processExitedUnexpectedly(exitCode)))
        }
        continuation.finish()
        self.continuation = nil
    }

    // MARK: - Private — cleanup

    private func tearDown() {
        pollingSource?.cancel()
        pollingSource = nil
        logHandle?.closeFile()
        logHandle = nil
        if let lp = logPath {
            try? FileManager.default.removeItem(atPath: lp)
            logPath = nil
        }
        if let ep = expPath {
            try? FileManager.default.removeItem(atPath: ep)
            expPath = nil
        }
    }

    // MARK: - Private — Expect script generation

    /// Returns an Expect script that spawns photorec and navigates its ncurses TUI
    /// automatically.  All photorec output is captured to `logPath` via
    /// Expect's `log_file`.  The exit sentinel `__HEYSOS_EXIT__:N` is appended
    /// to `logPath` after photorec exits so PhotoRecTask can recover the real exit code.
    ///
    /// ## TUI navigation sequence (photorec 7.2, USB drive)
    /// 1. Disk selection screen  — "Proceed" at bottom → Enter
    /// 2. Partition table type   — "Proceed" again (Intel selected) → Enter
    /// 3. Partition selection    — "Search" at bottom → Enter (first / only partition)
    /// 4. Filesystem type        — "ext2/ext3" default → Down arrow selects "Other" → Enter
    /// 5. Coverage choice        — "to be analysed" prompt → Enter (Free) or Down+Enter (Whole)
    /// 6. Recovery runs          — "files recovered" or eof marks completion
    private func makeExpectScript(
        binary: String,
        outDir: String,
        device: String,
        logPath: String,
        sentinel: String,
        options: ScanOptions
    ) -> String {
        // Escape backslashes and double-quotes for embedding in a Tcl string literal.
        let q = { (s: String) -> String in
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }
        // Tcl fragment to send when the Free/Whole coverage screen appears.
        let coverageSend = options.scanWholePartition
            ? "send \"\\033\\[B\"\\nafter 200\\nsend \"\\r\""
            : "send \"\\r\""
        return """
        #!/usr/bin/expect -f
        # Auto-generated by HeySOS — do not edit

        set timeout 7200
        log_user 0
        log_file -a "\(q(logPath))"

        spawn "\(q(binary))" /d "\(q(outDir))" "\(q(device))"

        # Navigate all screens with exp_continue so we loop until eof/timeout.
        # Patterns are matched against raw terminal output (including ANSI codes);
        # the key text strings below are always present regardless of decoration.
        expect {
            "Proceed" {
                # Disk selection or partition-table-type screen: confirm selection
                send "\\r"
                exp_continue
            }
            "Search" {
                # Partition selection screen: start recovery on selected partition
                send "\\r"
                exp_continue
            }
            "ext2/ext3" {
                # Filesystem type: default is ext2/ext3; move Down to select "Other"
                # then confirm — "Other" is better for unknown/FAT/NTFS USB drives
                send "\\033\\[B"
                after 300
                send "\\r"
                exp_continue
            }
            "to be analysed" {
                # Coverage screen: Free (unallocated only) or Whole (entire partition).
                # The highlighted default is Free; send Down+Enter to choose Whole.
                \(coverageSend)
                exp_continue
            }
            "recup_dir" {
                # Output dir browser: current dir is recup_dir; press C to confirm
                send "c"
                exp_continue
            }
            "Answer Y to really Quit" {
                # PhotoRec failed to write its .photorec.ses resume file (common on
                # read-only source disks).  Reply N to resume; scan continues without
                # session-save support — all files recovered so far are kept.
                send "n"
                exp_continue
            }
            "files saved in" {
                # PhotoRec finished — the summary screen is showing.
                # Send q to dismiss the [ Quit ] button and let photorec exit.
                after 500
                send "q"
            }
            eof { }
            timeout {
                puts "\\n\\[HeySOS: photorec timed out after 2 hours\\]\\n"
            }
        }

        # Capture photorec's real exit code and write the sentinel to the log.
        catch {wait} result
        set ecode [lindex $result 3]
        after 500
        set fh [open "\(q(logPath))" a]
        puts $fh "\\n\(sentinel):${ecode}"
        close $fh
        """
    }

    // MARK: - Private — helpers

    /// Resolve the photorec binary.
    /// The bundled binary (a copy of the Homebrew build, compiled with ncurses)
    /// is preferred so the app works without Homebrew installed.
    /// Homebrew is used as a fallback in case the bundle copy is missing.
    private func resolveBinaryURL(name: String) -> URL? {
        // 1. App bundle — ncurses-enabled build (driven by the Expect script)
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }
        // 2. Homebrew fallback (Apple Silicon then Intel)
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Strip ANSI/VT100 escape sequences and bare carriage returns from `s`.
    ///
    /// Handles:
    /// - CSI sequences: `ESC [ … final-byte` (cursor moves, colours, erase, etc.)
    /// - OSC sequences: `ESC ] … (BEL | ST)`
    /// - Other two-char ESC sequences: `ESC <single-char>`
    /// - Bare `\r` left by ncurses full-screen redraws
    private static func stripANSI(_ s: String) -> String {
        // Build patterns once and cache them.
        struct Patterns {
            // CSI:  ESC [ (param/intermediate bytes 0x20–0x3F)* (final byte 0x40–0x7E)
            static let csi  = try! NSRegularExpression(pattern: #"\x1B\[[\ -\x3F]*[\x40-\x7E]"#)
            // OSC:  ESC ] … BEL  or  ESC ] … ESC \
            static let osc  = try! NSRegularExpression(pattern: #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\\\)"#)
            // Other ESC sequences (ESC + one non-[ non-] char)
            static let esc  = try! NSRegularExpression(pattern: #"\x1B[^\[\]]"#)
        }
        var out = s
        let full = { NSRange(out.startIndex..., in: out) }
        out = Patterns.csi.stringByReplacingMatches(in: out, range: full(), withTemplate: "")
        out = Patterns.osc.stringByReplacingMatches(in: out, range: full(), withTemplate: "")
        out = Patterns.esc.stringByReplacingMatches(in: out, range: full(), withTemplate: "")
        // Normalise carriage-returns from ncurses full-screen redraws.
        out = out.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(of: "\r",   with: "\n")
        return out
    }

    private static func formatSpeed(sectors: Int64, seconds: Int) -> String {
        guard seconds > 0, sectors > 0 else { return "—" }
        let mbPerSec = (Double(sectors) * 512.0 / Double(seconds)) / 1_048_576.0
        return String(format: "%.1f MB/s", mbPerSec)
    }
}
