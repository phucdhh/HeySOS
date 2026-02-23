// StorageDevice.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// Represents a physical or virtual storage device visible to the system.
struct StorageDevice: Identifiable, Hashable {

    // MARK: - Properties

    /// Unique device node path, e.g. /dev/disk2
    let id: String

    /// Human-readable device name, e.g. "SONY 64GB"
    let name: String

    /// Total capacity in bytes
    let size: Int64

    /// File system type, e.g. "FAT32", "exFAT", "APFS"
    let fileSystem: String

    /// Whether this is an external (removable) device
    let isExternal: Bool

    /// Mount point if mounted, e.g. /Volumes/SONY — nil if unmounted
    let mountPoint: String?

    /// Categorised device type for UI icon selection
    let mediaType: MediaType

    // MARK: - Computed

    /// Formatted size string, e.g. "59.7 GB"
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Short display name combining name + size
    var displayTitle: String { "\(name) — \(formattedSize)" }
}

// MARK: - MediaType

enum MediaType: String, CaseIterable {
    case sdCard    = "SD Card"
    case usb       = "USB Drive"
    case ssd       = "External SSD"
    case hdd       = "External HDD"
    case internal_ = "Internal Drive"
    case diskImage = "Disk Image"
    case unknown   = "Unknown"

    var symbolName: String {
        switch self {
        case .sdCard:    return "memorychip"
        case .usb:       return "externaldrive.fill"
        case .ssd:       return "externaldrive.fill.badge.checkmark"
        case .hdd:       return "internaldrive"
        case .internal_: return "macpro.gen3"
        case .diskImage: return "doc.zipper"
        case .unknown:   return "questionmark.circle"
        }
    }
}
