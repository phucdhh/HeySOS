// DiskUtilWrapper.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// Wraps `diskutil list -plist` to enumerate storage devices.
///
/// Uses `diskutil list -plist` (machine-readable XML) for robustness across macOS versions.
/// Also calls `diskutil info -plist <disk>` per-disk to get volume name and mount point.
enum DiskUtilWrapper {

    enum DiskUtilError: LocalizedError {
        case diskutilNotFound
        case plistParseFailure
        case processError(Int32)

        var errorDescription: String? {
            switch self {
            case .diskutilNotFound:    return "diskutil not found at /usr/sbin/diskutil."
            case .plistParseFailure:   return "Failed to parse diskutil plist output."
            case .processError(let c): return "diskutil exited with code \(c)."
            }
        }
    }

    // MARK: - Public API

    /// Enumerate all storage devices visible to macOS.
    /// Safe to call from any thread; does not touch UI.
    static func listDevices() throws -> [StorageDevice] {
        let listData = try run(arguments: ["list", "-plist"])
        return try parseList(listData)
    }

    // MARK: - Private — Process runner

    private static func run(arguments: [String]) throws -> Data {
        let url = URL(fileURLWithPath: "/usr/sbin/diskutil")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw DiskUtilError.diskutilNotFound
        }

        let proc = Process()
        proc.executableURL = url
        proc.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe

        try proc.run()
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard proc.terminationStatus == 0 else {
            throw DiskUtilError.processError(proc.terminationStatus)
        }
        return data
    }

    // MARK: - Private — Parse `diskutil list -plist`

    /// Parses the top-level AllDisksAndPartitions array.
    /// Each entry is a whole disk with optional Partitions sub-array.
    private static func parseList(_ data: Data) throws -> [StorageDevice] {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let root = plist as? [String: Any],
            let allDisks = root["AllDisksAndPartitions"] as? [[String: Any]]
        else {
            throw DiskUtilError.plistParseFailure
        }

        var devices: [StorageDevice] = []

        for diskDict in allDisks {
            guard let devID = diskDict["DeviceIdentifier"] as? String else { continue }

            // Fetch per-disk detail for richer info (name, mount point, FS)
            let detail = (try? run(arguments: ["info", "-plist", "/dev/\(devID)"]))
                .flatMap { try? parseDiskInfo($0) }

            let name       = detail?.name       ?? devID
            let size       = detail?.size       ?? (diskDict["Size"] as? Int64 ?? 0)
            let fileSystem = detail?.fileSystem ?? (diskDict["Content"] as? String ?? "Unknown")
            let mountPoint = detail?.mountPoint
            let isExternal = detail?.isExternal ?? !devID.hasPrefix("disk0")
            let mediaType  = detail?.mediaType  ?? inferMediaType(devID: devID, isExternal: isExternal)

            devices.append(StorageDevice(
                id: "/dev/\(devID)",
                name: name,
                size: size,
                fileSystem: fileSystem,
                isExternal: isExternal,
                mountPoint: mountPoint,
                mediaType: mediaType
            ))
        }

        // External first, then internal
        return devices.sorted { $0.isExternal && !$1.isExternal }
    }

    // MARK: - Private — Parse `diskutil info -plist <disk>`

    private struct DiskDetail {
        var name: String
        var size: Int64
        var fileSystem: String
        var mountPoint: String?
        var isExternal: Bool
        var mediaType: MediaType
    }

    private static func parseDiskInfo(_ data: Data) throws -> DiskDetail {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let d = plist as? [String: Any]
        else { throw DiskUtilError.plistParseFailure }

        let devID      = d["DeviceIdentifier"] as? String ?? ""
        let name       = d["VolumeName"] as? String
                      ?? d["MediaName"] as? String
                      ?? devID
        let size       = (d["TotalSize"] as? Int64)
                      ?? (d["Size"] as? Int64)
                      ?? 0
        let fs         = d["FilesystemType"] as? String
                      ?? d["Content"] as? String
                      ?? "Unknown"
        let mountPoint = d["MountPoint"] as? String
        let removable  = d["RemovableMediaOrExternalDevice"] as? Bool
                      ?? d["Removable"] as? Bool
                      ?? !devID.hasPrefix("disk0")

        let mediaType  = inferMediaType(
            devID: devID,
            isExternal: removable,
            busProtocol: d["BusProtocol"] as? String,
            mediaType: d["MediaType"] as? String
        )

        return DiskDetail(
            name: name,
            size: size,
            fileSystem: fs,
            mountPoint: mountPoint.map { $0.isEmpty ? nil : $0 } ?? nil,
            isExternal: removable,
            mediaType: mediaType
        )
    }

    // MARK: - Private — MediaType inference

    private static func inferMediaType(
        devID: String,
        isExternal: Bool,
        busProtocol: String? = nil,
        mediaType: String? = nil
    ) -> MediaType {
        if !isExternal { return .internal_ }

        switch busProtocol?.lowercased() {
        case "sd":                   return .sdCard
        case "usb":
            // USB SSD vs USB thumb drive: use size heuristics in caller if needed
            return .usb
        case "pcie", "nvme":         return .ssd
        case "sata", "ata":          return .hdd
        default: break
        }

        // Fallback: if mediaType string hints at "generic"
        if mediaType?.lowercased().contains("solid") == true { return .ssd }

        return .unknown
    }
}
