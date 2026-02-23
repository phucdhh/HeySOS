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
            return "Could not find the '\(name)' binary inside the app bundle."
        case .insufficientPermissions:
            return "HeySOS needs Full Disk Access to scan this device. Please grant access in System Settings → Privacy & Security → Full Disk Access."
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

/// Central coordinator for all recovery operations.
/// Spawns PhotoRecTask / TestDiskTask and aggregates events.
@MainActor
final class RecoveryManager: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var recoveredFiles: [RecoveredFile] = []
    @Published private(set) var progressPercent: Double = 0
    @Published private(set) var filesFound: Int = 0
    @Published private(set) var currentSpeed: String = ""
    @Published private(set) var lastError: RecoveryError?

    // MARK: - Private

    private var photoRecTask: PhotoRecTask?
    private var eventStream: AsyncStream<RecoveryEvent>.Continuation?

    // MARK: - Public API

    /// Start a PhotoRec recovery session on the given device.
    /// - Parameters:
    ///   - device: The storage device to scan.
    ///   - outputDir: Directory where recovered files will be written.
    func startPhotoRecRecovery(device: StorageDevice, outputDir: URL) async {
        guard !isRunning else { return }
        isRunning = true
        recoveredFiles = []
        progressPercent = 0
        filesFound = 0
        lastError = nil

        let task = PhotoRecTask()
        self.photoRecTask = task

        let stream = task.start(device: device, outputDir: outputDir)

        for await event in stream {
            handle(event: event)
            if case .completed = event { break }
            if case .failed = event { break }
            if case .cancelled = event { break }
        }

        isRunning = false
    }

    /// Cancel the running recovery session.
    func cancel() {
        photoRecTask?.cancel()
    }

    // MARK: - Private

    private func handle(event: RecoveryEvent) {
        switch event {
        case .progress(let found, let speed, let pct):
            filesFound = found
            currentSpeed = speed
            progressPercent = pct
        case .fileRecovered(let name, let type, let size):
            // TODO: Construct full RecoveredFile from outputDir + name
            _ = (name, type, size)
        case .completed(let total, let dir):
            filesFound = total
            _ = dir
        case .failed(let error):
            lastError = error
        case .cancelled:
            break
        }
    }
}
