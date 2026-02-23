// DiskUtilWrapper.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// Wraps `diskutil list -plist` to enumerate storage devices.
///
/// Uses `diskutil list -plist` (machine-readable XML) rather than
/// parsing human-readable text output, for robustness across macOS versions.
enum DiskUtilWrapper {

    // MARK: - Public API

    /// Synchronously enumerate all storage devices visible to macOS.
    /// Call from a background Task to avoid blocking the main thread.
    static func listDevices() throws -> [StorageDevice] {
        let output = try run(arguments: ["list", "-plist"])
        return try parsePlist(output)
    }

    // MARK: - Private

    private static func run(arguments: [String]) throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        proc.arguments = arguments

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe() // swallow stderr

        try proc.run()
        proc.waitUntilExit()

        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    /// Parse `diskutil list -plist` XML output into StorageDevice array.
    private static func parsePlist(_ data: Data) throws -> [StorageDevice] {
        guard let plist = try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any],
              let allDisks = plist["AllDisksAndPartitions"] as? [[String: Any]]
        else {
            return []
        }

        var devices: [StorageDevice] = []

        for diskDict in allDisks {
            guard let devID = diskDict["DeviceIdentifier"] as? String else { continue }
            let devNode = "/dev/\(devID)"
            let name = diskDict["VolumeName"] as? String ?? devID
            let size = diskDict["Size"] as? Int64 ?? 0
            let fs = diskDict["Content"] as? String ?? "Unknown"

            // heuristic: external if not disk0 (internal boot drive)
            let isExternal = !devID.hasPrefix("disk0")

            devices.append(StorageDevice(
                id: devNode,
                name: name,
                size: size,
                fileSystem: fs,
                isExternal: isExternal,
                mountPoint: diskDict["MountPoint"] as? String,
                mediaType: .unknown // TODO: refine using IOKit
            ))
        }

        return devices
    }
}
