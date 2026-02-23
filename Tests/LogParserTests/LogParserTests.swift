// LogParserTests.swift
// HeySOS — Unit Tests
// Tests PhotoRecLogParser and TestDiskLogParser with captured real output samples.

import Testing
@testable import HeySOSCore

// MARK: - PhotoRec Log Parser Tests

@Suite("PhotoRec Log Parser")
struct PhotoRecLogParserTests {

    // MARK: - Sector progress line

    @Test("Parses sector progress line correctly")
    func parseSectorProgressLine() {
        let line = "Pass 1 - Reading sector     32768/124735488, 14 files found"
        var result = PhotoRecLogParser.ParseResult()
        PhotoRecLogParser.parseLine(line, into: &result)

        #expect(result.currentSector == 32768)
        #expect(result.totalSectors == 124735488)
        #expect(result.filesFound == 14)
    }

    @Test("Computes fraction correctly at 50%")
    func fractionCalculation() {
        var result = PhotoRecLogParser.ParseResult()
        result.currentSector = 62367744
        result.totalSectors  = 124735488

        #expect(abs((result.fraction ?? 0) - 0.5) < 0.001)
        #expect(result.percentString == "50.0%")
    }

    @Test("Fraction is nil when totalSectors is zero")
    func fractionNilWhenTotalZero() {
        let result = PhotoRecLogParser.ParseResult()
        #expect(result.fraction == nil)
    }

    // MARK: - Elapsed time line

    @Test("Parses elapsed and estimated time")
    func parseElapsedTimeLine() {
        let line = "Elapsed time 0h05m23s - Estimated time for achievement 0h17m51s"
        var result = PhotoRecLogParser.ParseResult()
        PhotoRecLogParser.parseLine(line, into: &result)

        #expect(result.elapsedSeconds == 323)    // 5*60+23
        #expect(result.estimatedSeconds == 1071) // 17*60+51
    }

    @Test("Parses small elapsed time values")
    func parseElapsedTimeSmall() {
        let line = "Elapsed time 0h00m02s - Estimated time for achievement 0h00m30s"
        var result = PhotoRecLogParser.ParseResult()
        PhotoRecLogParser.parseLine(line, into: &result)

        #expect(result.elapsedSeconds == 2)
        #expect(result.estimatedSeconds == 30)
    }

    // MARK: - File type count line

    @Test("Parses single file type count")
    func parseFileTypeCountJpg() {
        let line = "jpg: 14 recovered"
        var result = PhotoRecLogParser.ParseResult()
        PhotoRecLogParser.parseLine(line, into: &result)

        #expect(result.recoveredTypes["jpg"] == 14)
    }

    @Test("Parses multiple file type counts and sums filesFound")
    func parseMultipleFileTypes() {
        let lines = ["jpg: 12 recovered", "png:  2 recovered", "mp4:  1 recovered"]
        var result = PhotoRecLogParser.ParseResult()
        for line in lines { PhotoRecLogParser.parseLine(line, into: &result) }

        #expect(result.recoveredTypes["jpg"] == 12)
        #expect(result.recoveredTypes["png"] == 2)
        #expect(result.recoveredTypes["mp4"] == 1)
        #expect(result.filesFound >= 15)
    }

    // MARK: - Completion line

    @Test("Sets isCompleted on completion line")
    func parseCompletionLine() {
        let line = "Recovery completed."
        var result = PhotoRecLogParser.ParseResult()
        PhotoRecLogParser.parseLine(line, into: &result)

        #expect(result.isCompleted == true)
    }

    // MARK: - Full chunk

    @Test("Parses a full multi-line PhotoRec chunk")
    func parseFullChunk() {
        let chunk = """
        PhotoRec 7.2, Data Recovery Utility, April 2023
        Disk /dev/disk2 - 64 GB / 59 GiB
        Pass 1 - Reading sector     65536/124735488, 8 files found
        Elapsed time 0h00m04s - Estimated time for achievement 0h25m17s
        jpg:  8 recovered
        Pass 1 - Reading sector    131072/124735488, 22 files found
        Elapsed time 0h00m08s - Estimated time for achievement 0h23m46s
        jpg: 20 recovered
        png:  2 recovered
        Recovery completed.
        """
        let result = PhotoRecLogParser.parseChunk(chunk)

        #expect(result.currentSector == 131072)
        #expect(result.totalSectors == 124735488)
        #expect(result.recoveredTypes["jpg"] == 20)
        #expect(result.recoveredTypes["png"] == 2)
        #expect(result.isCompleted == true)
        #expect(result.fraction != nil)
    }

    // MARK: - Edge cases

    @Test("Empty and whitespace-only lines are ignored")
    func emptyAndWhitespaceLinesIgnored() {
        var result = PhotoRecLogParser.ParseResult()
        PhotoRecLogParser.parseLine("", into: &result)
        PhotoRecLogParser.parseLine("   ", into: &result)
        #expect(result.filesFound == 0)
        #expect(result.isCompleted == false)
    }

    @Test("Unrecognised lines do not modify results")
    func garbageLineIgnored() {
        var result = PhotoRecLogParser.ParseResult()
        PhotoRecLogParser.parseLine("some random output we don't understand", into: &result)
        #expect(result.totalSectors == 0)
    }
}

// MARK: - TestDisk Log Parser Tests

@Suite("TestDisk Log Parser")
struct TestDiskLogParserTests {

    /// Sample testdisk.log partition section (real output format)
    let sampleLog = """
    TestDisk 7.2, Data Recovery Utility, April 2023
    Christophe GRENIER <grenier@cgsecurity.org>
    https://www.cgsecurity.org

    Disk /dev/disk2 - 64 GB / 59 GiB - CHS 7763 255 63
         Partition               Start        End    Size in sectors
     P  W95 FAT32              0   0  1 7762 254 63  124735488
     D  Linux                  7763   0  1 7900 254 63    2241792
    """

    @Test("Parses two partitions from sample log")
    func parsesPartitionsFromLog() {
        let partitions = TestDiskLogParser.parse(sampleLog)
        #expect(partitions.count == 2)
    }

    @Test("First partition is primary FAT32")
    func firstPartitionIsPrimaryFAT32() {
        let partitions = TestDiskLogParser.parse(sampleLog)
        guard partitions.count >= 1 else {
            Issue.record("No partitions found")
            return
        }
        let p = partitions[0]
        #expect(p.status == .primary)
        #expect(p.type.contains("FAT32"))
        #expect(p.size == 124735488 * 512)
    }

    @Test("Second partition is deleted")
    func secondPartitionIsDeleted() {
        let partitions = TestDiskLogParser.parse(sampleLog)
        guard partitions.count >= 2 else {
            Issue.record("Expected 2 partitions")
            return
        }
        #expect(partitions[1].status == .deleted)
    }

    @Test("Empty log returns empty array")
    func emptyLogReturnsEmpty() {
        #expect(TestDiskLogParser.parse("").isEmpty)
    }

    @Test("Log without partitions returns empty array")
    func logWithNoPartitionSectionReturnsEmpty() {
        let log = """
        TestDisk 7.2, Data Recovery Utility
        Disk /dev/disk2 - 64 GB
        No partition found or selected for recovery
        """
        #expect(TestDiskLogParser.parse(log).isEmpty)
    }
}

