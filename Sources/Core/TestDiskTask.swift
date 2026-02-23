// TestDiskTask.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// Events emitted during a TestDisk analysis session.
enum TestDiskEvent {
    case partitionFound(index: Int, type: String, size: Int64, status: PartitionStatus)
    case analysisComplete(partitions: [PartitionInfo])
    case failed(error: RecoveryError)
    case cancelled
}

enum PartitionStatus: String {
    case primary   = "P"
    case deleted   = "D"
    case logical   = "L"
    case extended  = "E"
}

struct PartitionInfo: Identifiable, Hashable {
    let id: Int
    let type: String
    let size: Int64
    let status: PartitionStatus
    let startSector: UInt64
    let endSector: UInt64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// Wraps the TestDisk binary as an async subprocess.
///
/// v1.0 scope: **READ-ONLY** modes only (Analyse, List).
/// Write partition table is deferred to v1.3.
///
/// TestDisk batch mode (non-interactive):
///   testdisk /log /cmd "/dev/disk2,analyse,list"
///
/// testdisk writes a `testdisk.log` file in the current working directory.
/// We parse that log for structured partition output.
actor TestDiskTask {

    // MARK: - State

    private var process: Process?

    // MARK: - Public API

    /// Run TestDisk in analyse mode (read-only).
    ///
    /// - Parameter device: The device to analyse.
    /// - Returns: An `AsyncStream<TestDiskEvent>`.
    func analyse(device: StorageDevice) -> AsyncStream<TestDiskEvent> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            Task { await self.launch(device: device, continuation: continuation) }
        }
    }

    /// Cancel the running process.
    func cancel() {
        process?.terminate()
    }

    // MARK: - Private

    private func launch(
        device: StorageDevice,
        continuation: AsyncStream<TestDiskEvent>.Continuation
    ) {
        guard let binaryURL = resolveBinaryURL(name: "testdisk") else {
            continuation.yield(.failed(error: .binaryNotFound("testdisk")))
            continuation.finish()
            return
        }

        // testdisk writes log to CWD — use a temp directory
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeySOS-testdisk-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = binaryURL
        proc.currentDirectoryURL = tmpDir
        // Read-only: ends with "list" — never "write"
        proc.arguments = ["/log", "/cmd", "\(device.id),analyse,list"]

        let stderrPipe = Pipe()
        proc.standardOutput = stderrPipe   // testdisk writes output to stderr in log mode
        proc.standardError  = stderrPipe

        proc.terminationHandler = { [weak self] p in
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let logURL = tmpDir.appendingPathComponent("testdisk.log")
            let partitions = TestDiskLogParser.parseLog(at: logURL)

            Task {
                await self?.handleTermination(
                    exitCode: p.terminationStatus,
                    partitions: partitions,
                    tmpDir: tmpDir,
                    continuation: continuation
                )
            }
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            continuation.yield(.failed(error: .binaryNotFound("testdisk")))
            continuation.finish()
        }
    }

    private func handleTermination(
        exitCode: Int32,
        partitions: [PartitionInfo],
        tmpDir: URL,
        continuation: AsyncStream<TestDiskEvent>.Continuation
    ) {
        // Emit each found partition
        for p in partitions {
            continuation.yield(.partitionFound(
                index: p.id,
                type: p.type,
                size: p.size,
                status: p.status
            ))
        }

        if exitCode == 0 || !partitions.isEmpty {
            continuation.yield(.analysisComplete(partitions: partitions))
        } else if exitCode == 15 {
            continuation.yield(.cancelled)
        } else {
            continuation.yield(.failed(error: .processExitedUnexpectedly(exitCode)))
        }
        continuation.finish()

        // Clean up temp directory
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func resolveBinaryURL(name: String) -> URL? {
        // 1. App bundle — individual file resource (lands in Contents/Resources/)
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }
        // 2. Homebrew fallback
        for path in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
