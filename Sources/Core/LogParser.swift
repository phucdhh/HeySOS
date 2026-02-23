// LogParser.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

// MARK: - PhotoRec Log Parser

/// Parses PhotoRec stdout output into structured RecoveryEvent values.
///
/// PhotoRec --cmd batch mode stdout format (approximate):
///   Pass 1 - Reading sector  102400/1048576, 14 files found
///   Elapsed time 0h00m05s - Estimated time for achievement 0h00m30s
///   jpg: 12 recovered
///   png:  2 recovered
///
/// NOTE: The exact format varies by PhotoRec version and platform.
/// Unit tests MUST be written with captured real stdout samples.
///   See: Tests/LogParserTests/
enum PhotoRecLogParser {

    struct ParseResult {
        var filesFound: Int = 0
        var percent: Double = 0
        var speed: String = ""
    }

    /// Parse a chunk of PhotoRec stdout text.
    /// - Returns: A `ParseResult` if relevant data was found, nil otherwise.
    static func parse(line: String) -> ParseResult? {
        // TODO (Milestone 1.4): Implement with regex/state machine
        // Patterns to match:
        //   "Pass \d+ - Reading sector\s+(\d+)/(\d+),\s+(\d+) files found"
        //   "Elapsed time (\S+) - Estimated time .+"
        _ = line
        return nil
    }
}

// MARK: - TestDisk Log Parser

/// Parses testdisk.log output into PartitionInfo values.
enum TestDiskLogParser {

    /// Parse a testdisk.log file and extract partition entries.
    static func parseLog(at url: URL) -> [PartitionInfo] {
        // TODO (Milestone 1.3): Implement partition table log parsing
        _ = url
        return []
    }
}
