// RecoveryManager.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// Events emitted during a recovery session.
enum RecoveryEvent {
    case progress(filesFound: Int, speed: String, percent: Double)
    case fileRecovered(name: String, type: String, size: Int64)
    case completed(totalFiles: Int, outputDir: URL)
    case failed(error: RecoveryError)
    case cancelled
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

    // MARK: - Private

    private var photoRecTask: PhotoRecTask?

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
    ///   - fileTypes: PhotoRec file type selector string (default: recover everything).
    func startRecovery(
        device: StorageDevice,
        outputDir: URL,
        fileTypes: String = "everything,enable"
    ) async {
        guard !isRunning else { return }

        resetSessionState()
        isRunning = true
        activeOutputDir = outputDir

        let task = PhotoRecTask()
        self.photoRecTask = task

        let stream = await task.start(device: device, outputDir: outputDir, fileTypes: fileTypes)

        for await event in stream {
            handle(event: event)
            if case .completed = event { break }
            if case .failed    = event { break }
            if case .cancelled = event { break }
        }

        isRunning = false

        // After completion: enumerate recovered files from outputDir
        if lastError == nil {
            await enumerateRecoveredFiles(in: outputDir)
        }
    }

    /// Cancel the ongoing recovery session.
    func cancelRecovery() {
        Task { await photoRecTask?.cancel() }
    }

    // MARK: - Private

    private func resetSessionState() {
        recoveredFiles = []
        progressPercent = 0
        filesFound = 0
        currentSpeed = ""
        estimatedSecondsRemaining = 0
        lastError = nil
        activeOutputDir = nil
    }

    private func handle(event: RecoveryEvent) {
        switch event {
        case .progress(let found, let speed, let pct):
            filesFound = found
            currentSpeed = speed
            progressPercent = pct

        case .fileRecovered(let name, let type, let size):
            // PhotoRec --cmd doesn't emit per-file events; we enumerate after completion.
            // This case is available for future per-file parsers.
            _ = (name, type, size)

        case .completed(let total, _):
            filesFound = total

        case .failed(let error):
            lastError = error

        case .cancelled:
            break
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

    private nonisolated static func scanDirectory(_ dir: URL) -> [RecoveredFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [RecoveredFile] = []
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }

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
        return files.sorted { $0.name < $1.name }
    }
}
