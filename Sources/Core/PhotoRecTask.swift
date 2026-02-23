// PhotoRecTask.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// Wraps the PhotoRec binary as an async subprocess.
///
/// PhotoRec is an ncurses TUI — it CANNOT be driven via interactive stdin.
/// Instead, we use the `--cmd` batch mode documented at:
/// https://www.cgsecurity.org/wiki/PhotoRec_Command_Line
///
/// Example command:
///   photorec /d /path/to/output /cmd "/dev/disk2,fileopt,everything,enable,search"
actor PhotoRecTask {

    // MARK: - State

    private var process: Process?
    private var continuation: AsyncStream<RecoveryEvent>.Continuation?

    // MARK: - Public API

    /// Launch PhotoRec in non-interactive `--cmd` mode.
    /// - Returns: An `AsyncStream` of `RecoveryEvent` values.
    func start(device: StorageDevice, outputDir: URL) -> AsyncStream<RecoveryEvent> {
        AsyncStream { continuation in
            self.continuation = continuation

            guard let binaryURL = Bundle.main.url(
                forResource: "photorec",
                withExtension: nil,
                subdirectory: "Binaries"
            ) else {
                continuation.yield(.failed(error: .binaryNotFound("photorec")))
                continuation.finish()
                return
            }

            let proc = Process()
            proc.executableURL = binaryURL
            proc.arguments = [
                "/d", outputDir.path,
                "/cmd", "\(device.id),fileopt,everything,enable,search"
            ]

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            // Real-time stdout parsing via readabilityHandler
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else { return }
                Task { await self?.parse(output: text, continuation: continuation) }
            }

            proc.terminationHandler = { [weak self] p in
                Task {
                    await self?.handleTermination(exitCode: p.terminationStatus,
                                                  continuation: continuation)
                }
            }

            do {
                try proc.run()
                self.process = proc
            } catch {
                continuation.yield(.failed(error: .binaryNotFound("photorec")))
                continuation.finish()
            }
        }
    }

    /// Send SIGTERM to the running process.
    func cancel() {
        process?.terminate()
        continuation?.yield(.cancelled)
        continuation?.finish()
    }

    // MARK: - Private

    private func parse(output: String, continuation: AsyncStream<RecoveryEvent>.Continuation) {
        // TODO (Milestone 1.4): Implement LogParser-based parsing.
        // Emit .progress and .fileRecovered events based on PhotoRec stdout format.
        _ = (output, continuation)
    }

    private func handleTermination(exitCode: Int32,
                                   continuation: AsyncStream<RecoveryEvent>.Continuation) {
        if exitCode == 0 {
            // TODO: Parse final summary for total file count and outputDir
            continuation.yield(.completed(totalFiles: 0, outputDir: URL(fileURLWithPath: "/")))
        } else {
            continuation.yield(.failed(error: .processExitedUnexpectedly(exitCode)))
        }
        continuation.finish()
    }
}
