// PhotoRecTask.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// Wraps the PhotoRec binary as an async subprocess using `--cmd` batch mode.
///
/// ## Why --cmd mode?
/// PhotoRec is an ncurses TUI — driving it via stdin is impossible.
/// The `--cmd` flag runs a fully non-interactive session:
///
///   photorec /d /output/dir /cmd "/dev/disk2,fileopt,everything,enable,search"
///
/// Reference: https://www.cgsecurity.org/wiki/PhotoRec_Command_Line
actor PhotoRecTask {

    // MARK: - State

    private var process: Process?
    private var continuation: AsyncStream<RecoveryEvent>.Continuation?

    // Actor-isolated parse state — avoids Swift 6 data race on captured vars
    private var parseResult = PhotoRecLogParser.ParseResult()
    private var lastProgressYield = Date.distantPast

    // MARK: - Constants

    /// Interval (seconds) between progress yield events.
    private let progressThrottleInterval: TimeInterval = 0.5

    // MARK: - Public API

    /// Launch PhotoRec in non-interactive `--cmd` mode.
    ///
    /// - Parameters:
    ///   - device: The device to scan (must pass read-only; PhotoRec never writes to source).
    ///   - outputDir: Directory where recovered files will be written.
    ///   - fileTypes: Comma-separated PhotoRec file type list, e.g. `"everything,enable"`.
    ///                Defaults to recovering everything.
    /// - Returns: An `AsyncStream<RecoveryEvent>` that yields progress and completion events.
    func start(
        device: StorageDevice,
        outputDir: URL,
        fileTypes: String = "everything,enable"
    ) -> AsyncStream<RecoveryEvent> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }

            Task {
                await self.launch(
                    device: device,
                    outputDir: outputDir,
                    fileTypes: fileTypes,
                    continuation: continuation
                )
            }
        }
    }

    /// Send SIGTERM to the running process and emit a `.cancelled` event.
    func cancel() {
        process?.terminate()
        continuation?.yield(.cancelled)
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private — launch

    private func launch(
        device: StorageDevice,
        outputDir: URL,
        fileTypes: String,
        continuation: AsyncStream<RecoveryEvent>.Continuation
    ) {
        self.continuation = continuation

        // Resolve binary path from bundle, then fall back to Homebrew location
        let binaryURL = resolveBinaryURL(name: "photorec")

        guard let binaryURL else {
            continuation.yield(.failed(error: .binaryNotFound("photorec")))
            continuation.finish()
            return
        }

        // Ensure output directory exists
        do {
            try FileManager.default.createDirectory(
                at: outputDir,
                withIntermediateDirectories: true
            )
        } catch {
            continuation.yield(.failed(error: .outputDirectoryNotWritable(outputDir)))
            continuation.finish()
            return
        }

        let proc = Process()
        proc.executableURL = binaryURL

        // /d sets the output directory prefix; /cmd gives the non-interactive command string
        proc.arguments = [
            "/d", outputDir.path,
            "/cmd", "\(device.id),\(fileTypes),search"
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe

        // Route stdout through the actor to avoid Swift 6 data races.
        // readabilityHandler runs on a background thread; we hop to the actor via Task.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { await self?.processOutput(text, continuation: continuation) }
        }

        proc.terminationHandler = { [weak self] p in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            Task {
                await self?.handleTermination(
                    p.terminationStatus,
                    outputDir: outputDir,
                    continuation: continuation
                )
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

    // MARK: - Private — helpers

    /// Called on the actor — safely mutates actor-isolated parse state.
    private func processOutput(
        _ text: String,
        continuation: AsyncStream<RecoveryEvent>.Continuation
    ) {
        for line in text.components(separatedBy: .newlines) {
            PhotoRecLogParser.parseLine(line, into: &parseResult)
        }

        // Throttle progress events
        let now = Date()
        guard now.timeIntervalSince(lastProgressYield) >= progressThrottleInterval else { return }
        lastProgressYield = now

        continuation.yield(.progress(
            filesFound: parseResult.filesFound,
            speed: parseResult.elapsedSeconds > 0
                ? Self.formatSpeed(sectors: parseResult.currentSector,
                                   seconds: parseResult.elapsedSeconds)
                : "—",
            percent: parseResult.fraction.map { $0 * 100 } ?? 0
        ))
    }

    private func handleTermination(
        _ exitCode: Int32,
        outputDir: URL,
        continuation: AsyncStream<RecoveryEvent>.Continuation
    ) {
        if exitCode == 0 || parseResult.isCompleted {
            let total = parseResult.recoveredTypes.values.reduce(0, +)
            continuation.yield(.completed(totalFiles: total, outputDir: outputDir))
        } else if exitCode == 15 {
            continuation.yield(.cancelled)
        } else {
            continuation.yield(.failed(error: .processExitedUnexpectedly(exitCode)))
        }
        continuation.finish()
        self.continuation = nil
    }

    /// Resolve the photorec/testdisk binary: bundle first, Homebrew fallback.
    private func resolveBinaryURL(name: String) -> URL? {
        // 1. App bundle (production)
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Binaries"
        ) { return url }

        // 2. Development fallback: Homebrew
        let homebrewPaths = [
            "/opt/homebrew/bin/\(name)",   // Apple Silicon
            "/usr/local/bin/\(name)"       // Intel
        ]
        for path in homebrewPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Format scan speed: MB/s based on sectors scanned and elapsed time.
    private static func formatSpeed(sectors: Int64, seconds: Int) -> String {
        guard seconds > 0, sectors > 0 else { return "—" }
        let bytes = Double(sectors) * 512.0
        let mbPerSec = (bytes / Double(seconds)) / 1_048_576.0
        return String(format: "%.1f MB/s", mbPerSec)
    }
}
