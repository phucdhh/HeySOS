// RecoveryManager.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// Events emitted during a recovery session.
enum RecoveryEvent {
    case progress(filesFound: Int, speed: String, percent: Double, estimatedSeconds: Int)
    case fileRecovered(name: String, type: String, size: Int64)
    case completed(totalFiles: Int, outputDir: URL)
    case failed(error: RecoveryError)
    case cancelled
    /// Raw console output line(s) from the recovery engine.
    case log(String)
}

/// Errors that can occur during recovery.
enum RecoveryError: LocalizedError {
    case binaryNotFound(String)
    case insufficientPermissions
    case deviceNotFound(StorageDevice)
    case outputDirectoryNotWritable(URL)
    case processExitedUnexpectedly(Int32)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let name):
            return "Could not find the '\(name)' binary. Please run scripts/build-engines.sh or install TestDisk via Homebrew."
        case .insufficientPermissions:
            return "HeySOS needs Full Disk Access to scan this device.\nGo to: System Settings → Privacy & Security → Full Disk Access → enable HeySOS."
        case .deviceNotFound(let d):
            return "The device '\(d.name)' (\(d.id)) is no longer available."
        case .outputDirectoryNotWritable(let url):
            return "Cannot write to the output directory: \(url.path). Please choose a different location."
        case .processExitedUnexpectedly(let code):
            return "The recovery engine exited unexpectedly with code \(code)."
        case .cancelled:
            return "Recovery was cancelled by the user."
        }
    }
}

// MARK: - RecoveryManager

/// Central coordinator for all recovery operations.
@MainActor
final class RecoveryManager: ObservableObject {

    // MARK: - Published state

    @Published private(set) var devices: [StorageDevice] = []
    @Published private(set) var isLoadingDevices: Bool = false

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var recoveredFiles: [RecoveredFile] = []
    @Published private(set) var progressPercent: Double = 0
    @Published private(set) var filesFound: Int = 0
    @Published private(set) var currentSpeed: String = ""
    @Published private(set) var estimatedSecondsRemaining: Int = 0
    @Published private(set) var lastError: RecoveryError?
    @Published private(set) var activeOutputDir: URL?
    /// Scan options set by the user before starting.
    @Published var scanOptions: ScanOptions = ScanOptions()
    /// Accumulated raw console output from the recovery engine.
    @Published private(set) var consoleLog: String = ""

    // MARK: - Private

    private var photoRecTask: PhotoRecTask?

    // Log batching — avoids re-rendering SwiftUI Text on every 200 ms poll tick.
    // Incoming log chunks are buffered and flushed to `consoleLog` at most once
    // per `logFlushInterval`, keeping the main thread free during heavy scans.
    private var pendingLog: String = ""
    private var logFlushScheduled = false
    private let logFlushInterval: Duration = .milliseconds(800)
    /// Maximum number of lines kept in `consoleLog` to bound layout cost.
    private let maxLogLines = 500

    // Wall-clock progress interpolation — moves the bar smoothly between log events.
    private var progressInterpolTimer: Timer?
    private var progressBasePercent: Double = 0   // percent (0-99) at last .progress event
    private var progressBaseTime: Date = .distantPast
    private var progressBaseETA: Double = 1       // estimated seconds remaining at last event

    // MARK: - Device Discovery

    /// Load (or refresh) the list of storage devices.
    func loadDevices() async {
        guard !isLoadingDevices else { return }
        isLoadingDevices = true
        defer { isLoadingDevices = false }

        do {
            let found = try await Task.detached(priority: .userInitiated) {
                try DiskUtilWrapper.listDevices()
            }.value
            self.devices = found
        } catch {
            // Non-fatal — show empty list, user can retry
            self.devices = []
        }
    }

    // MARK: - Recovery

    /// Start a PhotoRec recovery session.
    ///
    /// - Parameters:
    ///   - device: Storage device to scan (read-only).
    ///   - outputDir: Directory where PhotoRec will write recovered files.
    func startRecovery(
        device: StorageDevice,
        outputDir: URL
    ) async {
        guard !isRunning else { return }

        resetSessionState()
        isRunning = true
        activeOutputDir = outputDir

        let task = PhotoRecTask()
        self.photoRecTask = task

        let stream = await task.start(device: device, outputDir: outputDir, options: scanOptions)

        for await event in stream {
            handle(event: event)
            if case .completed = event { break }
            if case .failed    = event { break }
            if case .cancelled = event { break }
        }

        isRunning = false

        // Flush any remaining buffered log text immediately.
        flushPendingLog()

        // Always enumerate recovered files — PhotoRec may have recovered files
        // even when it exits with a non-zero code (e.g. session-save failure).
        await enumerateRecoveredFiles(in: outputDir)
    }

    /// Cancel the ongoing recovery session.
    func cancelRecovery() {
        Task { await photoRecTask?.cancel() }
    }

    /// Reset results so the user can start a new scan.
    func resetRecovery() {
        stopProgressTimer()
        progressBasePercent = 0
        progressBaseTime = .distantPast
        progressBaseETA = 1
        recoveredFiles = []
        progressPercent = 0
        filesFound = 0
        currentSpeed = ""
        lastError = nil
        consoleLog = ""
    }

    // MARK: - Private

    private func resetSessionState() {
        stopProgressTimer()
        progressBasePercent = 0
        progressBaseTime = .distantPast
        progressBaseETA = 1
        recoveredFiles = []
        progressPercent = 0
        filesFound = 0
        currentSpeed = ""
        estimatedSecondsRemaining = 0
        lastError = nil
        activeOutputDir = nil
        consoleLog = ""
        pendingLog = ""
        logFlushScheduled = false
    }

    private func handle(event: RecoveryEvent) {
        switch event {
        case .progress(let found, let speed, let pct, let eta):
            filesFound = found
            currentSpeed = speed
            // Always accept an advancing percent from the parser.
            if pct > progressPercent { progressPercent = pct }
            // Only start the interpolation timer once we have a genuine ETA.
            // Without a real ETA, the default of 1 s would race the bar to 99%.
            if eta > 0 {
                estimatedSecondsRemaining = eta
                progressBasePercent = progressPercent
                progressBaseTime = Date()
                progressBaseETA = Double(eta)
                startProgressTimer()
            }

        case .fileRecovered(let name, let type, let size):
            // PhotoRec --cmd doesn't emit per-file events; we enumerate after completion.
            // This case is available for future per-file parsers.
            _ = (name, type, size)

        case .completed(let total, _):
            filesFound = total
            stopProgressTimer()
            progressPercent = 100

        case .failed(let error):
            stopProgressTimer()
            lastError = error

        case .cancelled:
            stopProgressTimer()

        case .log(let text):
            pendingLog += text
            scheduleLogFlush()
        }
    }

    /// Advances progressPercent smoothly using wall-clock time since the last .progress event.
    private func startProgressTimer() {
        guard progressInterpolTimer == nil else { return }
        progressInterpolTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let wall = Date().timeIntervalSince(self.progressBaseTime)
            // Each second of wall time represents 1 s / ETA of total distance.
            let advance = (wall / self.progressBaseETA) * 100.0
            let newPct = min(99.0, self.progressBasePercent + advance)
            if newPct > self.progressPercent {
                self.progressPercent = newPct
            }
        }
    }

    private func stopProgressTimer() {
        progressInterpolTimer?.invalidate()
        progressInterpolTimer = nil
    }

    /// Coalesces buffered log text into a single `consoleLog` publish,
    /// capped at `maxLogLines` lines to prevent SwiftUI layout hangs.
    private func scheduleLogFlush() {
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: logFlushInterval)
            self.flushPendingLog()
        }
    }

    private func flushPendingLog() {
        defer { logFlushScheduled = false }
        guard !pendingLog.isEmpty else { return }
        consoleLog += pendingLog
        pendingLog = ""
        // Cap to the most recent maxLogLines lines to bound Text layout cost.
        let lines = consoleLog.components(separatedBy: "\n")
        if lines.count > maxLogLines {
            consoleLog = lines.suffix(maxLogLines).joined(separator: "\n")
        }
    }

    /// Walk the output directory and build the `recoveredFiles` array.
    private func enumerateRecoveredFiles(in dir: URL) async {
        let found = await Task.detached(priority: .userInitiated) {
            Self.scanDirectory(dir)
        }.value
        self.recoveredFiles = found
        self.filesFound = found.count
    }

    private nonisolated static func scanDirectory(_ baseDir: URL) -> [RecoveredFile] {
        let fm = FileManager.default
        let parent   = baseDir.deletingLastPathComponent()
        let baseName = baseDir.lastPathComponent

        // PhotoRec writes recovered files into SIBLING directories named
        // with a numeric suffix: HeySOS_Recovered.1/, HeySOS_Recovered.2/ …
        // The baseDir itself may also contain recup_dir.N subdirectories
        // (older photorec behaviour), so always include it as a root.
        var searchRoots: [URL] = [baseDir]
        if let siblings = try? fm.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for sib in siblings {
                let name = sib.lastPathComponent
                guard name.hasPrefix(baseName + ".")
                else { continue }
                let suffix = name.dropFirst(baseName.count + 1)
                guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber })
                else { continue }
                var isDir: ObjCBool = false
                fm.fileExists(atPath: sib.path, isDirectory: &isDir)
                if isDir.boolValue { searchRoots.append(sib) }
            }
        }

        var files: [RecoveredFile] = []
        for root in searchRoots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir),
                      !isDir.boolValue else { continue }
                let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let size  = Int64(attrs?.fileSize ?? 0)
                let date  = attrs?.contentModificationDate ?? Date()
                files.append(RecoveredFile(
                    id: UUID(),
                    name: url.lastPathComponent,
                    fileExtension: url.pathExtension,
                    size: size,
                    recoveredAt: date,
                    fileURL: url
                ))
            }
        }
        return files.sorted { $0.name < $1.name }
    }
}
