// LogParser.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation
import RegexBuilder

// MARK: - PhotoRec Log Parser

/// Parses PhotoRec stdout/stderr output into structured RecoveryEvent values.
///
/// Tested against PhotoRec 7.2 `--cmd` batch mode output.
/// Sample output line formats:
///   "Pass 1 - Reading sector     32768/124735488, 14 files found"
///   "Elapsed time 0h00m02s - Estimated time for achievement 0h17m51s"
///   "jpg: 14 recovered"
///   "Recovery completed."
enum PhotoRecLogParser {

    // MARK: - Public result type

    struct ParseResult: Equatable {
        var currentSector: Int64   = 0
        var totalSectors: Int64    = 0
        var filesFound: Int        = 0
        var elapsedSeconds: Int    = 0
        var estimatedSeconds: Int  = 0
        var recoveredTypes: [String: Int] = [:]
        var isCompleted: Bool      = false

        /// 0.0 – 1.0 progress fraction.
        /// Uses sector-based progress when available, otherwise falls back to
        /// elapsed / (elapsed + estimated) so the bar moves smoothly even between
        /// full "Pass X - Reading sector" redraws.
        var fraction: Double? {
            if totalSectors > 0 && currentSector > 0 {
                return min(1.0, Double(currentSector) / Double(totalSectors))
            }
            let total = elapsedSeconds + estimatedSeconds
            guard total > 0 else { return nil }
            return min(0.99, Double(elapsedSeconds) / Double(total))
        }

        var percentString: String {
            guard let f = fraction else { return "—" }
            return String(format: "%.1f%%", f * 100)
        }
    }

    // MARK: - Public API

    /// Parse a single line from PhotoRec stdout.
    /// Accumulates state into the provided `result` (inout).
    public static func parseLine(_ line: String, into result: inout ParseResult) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if parseSectorProgress(trimmed, into: &result) { return }
        if parseElapsedTime(trimmed, into: &result)    { return }
        if parseFileTypeCount(trimmed, into: &result)  { return }
        if trimmed.hasPrefix("Recovery completed")     { result.isCompleted = true; return }
    }

    /// Parse a multi-line chunk of PhotoRec output.
    static func parseChunk(_ chunk: String) -> ParseResult {
        var result = ParseResult()
        for line in chunk.components(separatedBy: .newlines) {
            parseLine(line, into: &result)
        }
        return result
    }

    // MARK: - Private — individual line parsers

    /// "Pass 1 - Reading sector     32768/124735488, 14 files found"
    /// Also handles no-space variant: "Pass 1 - Reading sector5400/7864320, 0 files found"
    @discardableResult
    private static func parseSectorProgress(_ line: String, into r: inout ParseResult) -> Bool {
        guard line.hasPrefix("Pass") else { return false }

        // Sector fraction: digits/digits — \s* tolerates zero spaces (ncurses redraw)
        let sectorPattern = /Reading sector\s*(\d+)\/(\d+),\s*(\d+) file/
        guard let m = try? sectorPattern.firstMatch(in: line) else { return false }

        r.currentSector = Int64(m.output.1) ?? r.currentSector
        r.totalSectors  = Int64(m.output.2) ?? r.totalSectors
        r.filesFound    = Int(m.output.3)   ?? r.filesFound
        return true
    }

    /// "Elapsed time 0h05m23s - Estimated time to completion 0h17m51"
    /// The trailing 's' on estimated time is sometimes absent in PhotoRec 7.2 output.
    @discardableResult
    private static func parseElapsedTime(_ line: String, into r: inout ParseResult) -> Bool {
        guard line.hasPrefix("Elapsed time") else { return false }

        let timePattern = /(\d+)h(\d+)m(\d+)s?/
        // Use String.matches(of:) — returns a collection of Match objects
        let allMatches = line.matches(of: timePattern)
        guard !allMatches.isEmpty else { return false }

        // First match = elapsed, second match = estimated
        if allMatches.count >= 1 {
            let m = allMatches[0]
            r.elapsedSeconds = toHMS(m.output.1, m.output.2, m.output.3)
        }
        if allMatches.count >= 2 {
            let m = allMatches[1]
            r.estimatedSeconds = toHMS(m.output.1, m.output.2, m.output.3)
        }
        return true
    }

    /// "jpg: 14 recovered"  /  "png:  2 recovered"  /  "tx?: 1 recovered"
    @discardableResult
    private static func parseFileTypeCount(_ line: String, into r: inout ParseResult) -> Bool {
        // Extension names can include '?' (e.g. PhotoRec uses "tx?" for unknown text)
        let pattern = /^([a-zA-Z0-9?]+):\s+(\d+) recovered/
        guard let m = try? pattern.firstMatch(in: line) else { return false }
        let ext   = String(m.output.1).lowercased()
        let count = Int(m.output.2) ?? 0
        r.recoveredTypes[ext] = count
        // Update total filesFound from sum if line parsing missed it
        r.filesFound = max(r.filesFound, r.recoveredTypes.values.reduce(0, +))
        return true
    }

    private static func toHMS(_ h: Substring, _ m: Substring, _ s: Substring) -> Int {
        (Int(h) ?? 0) * 3600 + (Int(m) ?? 0) * 60 + (Int(s) ?? 0)
    }
}

// MARK: - TestDisk Log Parser

/// Parses testdisk.log output into PartitionInfo values.
///
/// testdisk /log emits a log file. The partition section looks like:
///   Partition              Start        End    Size in sectors
///  P FAT32              0   0  1 7762 254 63   124735488
enum TestDiskLogParser {

    // MARK: - Public API

    /// Parse a testdisk.log file and extract partition entries.
    static func parseLog(at url: URL) -> [PartitionInfo] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parseLines(content.components(separatedBy: .newlines))
    }

    /// Parse log text directly (for unit tests).
    static func parse(_ text: String) -> [PartitionInfo] {
        parseLines(text.components(separatedBy: .newlines))
    }

    // MARK: - Private

    /// Parse partition table lines from testdisk output.
    ///
    /// Format: ` P  W95 FAT32              0   0  1 7762 254 63  124735488`
    /// The type can be multi-word (e.g. "W95 FAT32", "Linux swap / Solaris").
    /// Separated from numbers by 2+ spaces.
    private static func parseLines(_ lines: [String]) -> [PartitionInfo] {
        var partitions: [PartitionInfo] = []
        var index = 0

        let validStatuses: Set<Character> = ["P", "D", "L", "E", "*", "d"]

        // Regex: status, multi-word type (2+ spaces as delimiter), then 7 numbers
        // Groups: 1=status 2=type 3=startC 4=startH 5=startS 6=endC 7=endH 8=endS 9=sectors
        let pattern = /^\s*([PDLEd*])\s+([\w\s\/\-]+?)\s{2,}(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/

        for line in lines {
            guard let first = line.first(where: { !$0.isWhitespace }),
                  validStatuses.contains(first) else { continue }
            guard let m = try? pattern.firstMatch(in: line) else { continue }

            let statusChar = String(m.output.1)
            let typeName   = String(m.output.2).trimmingCharacters(in: .whitespaces)
            let startCyl   = UInt64(m.output.3) ?? 0
            let endCyl     = UInt64(m.output.6) ?? 0
            let sectors    = Int64(m.output.9) ?? 0

            let status: PartitionStatus
            switch statusChar {
            case "P", "*": status = .primary
            case "D", "d": status = .deleted
            case "L":      status = .logical
            case "E":      status = .extended
            default:       status = .primary
            }

            partitions.append(PartitionInfo(
                id: index,
                type: typeName,
                size: sectors * 512,
                status: status,
                startSector: startCyl,
                endSector: endCyl
            ))
            index += 1
        }

        return partitions
    }
}
