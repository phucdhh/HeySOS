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
}

/// Wraps the TestDisk binary as an async subprocess.
///
/// v1.0 scope: READ-ONLY operations only (Analyse, List).
/// Write partition table is intentionally excluded — deferred to v1.3.
///
/// TestDisk batch mode:
///   testdisk /log /cmd "/dev/disk2,analyse,list"
///
/// NOTE: TestDisk writes a testdisk.log file alongside the target device.
/// Parse that log file for structured partition output.
actor TestDiskTask {

    // MARK: - State

    private var process: Process?

    // MARK: - Public API

    /// Run TestDisk in analyse mode (read-only).
    /// - Returns: An `AsyncStream` of `TestDiskEvent` values.
    func analyse(device: StorageDevice) -> AsyncStream<TestDiskEvent> {
        AsyncStream { continuation in
            guard let binaryURL = Bundle.main.url(
                forResource: "testdisk",
                withExtension: nil,
                subdirectory: "Binaries"
            ) else {
                continuation.yield(.failed(error: .binaryNotFound("testdisk")))
                continuation.finish()
                return
            }

            let proc = Process()
            proc.executableURL = binaryURL
            // Read-only: /cmd ends with "list" — never "write"
            proc.arguments = ["/log", "/cmd", "\(device.id),analyse,list"]

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                // TODO (Milestone 1.3): Parse TestDisk log output
                _ = data
            }

            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    // TODO: Parse testdisk.log for partition info
                    continuation.yield(.analysisComplete(partitions: []))
                } else {
                    continuation.yield(.failed(error: .processExitedUnexpectedly(p.terminationStatus)))
                }
                continuation.finish()
            }

            do {
                try proc.run()
                self.process = proc
            } catch {
                continuation.yield(.failed(error: .binaryNotFound("testdisk")))
                continuation.finish()
            }
        }
    }

    /// Cancel the running process.
    func cancel() {
        process?.terminate()
    }
}
