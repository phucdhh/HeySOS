// RecoveredFile.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import Foundation

/// A file that PhotoRec has successfully recovered.
struct RecoveredFile: Identifiable, Hashable {

    let id: UUID
    let name: String
    let fileExtension: String
    let size: Int64
    let recoveredAt: Date
    let fileURL: URL

    // MARK: - Computed

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var fileType: FileType {
        FileType(extension: fileExtension.lowercased())
    }
}

// MARK: - FileType

enum FileType: Hashable {
    case image
    case video
    case document
    case audio
    case archive
    case other(String)

    init(extension ext: String) {
        switch ext {
        case "jpg", "jpeg", "png", "raw", "cr2", "arw", "nef", "dng", "heic", "tiff", "bmp":
            self = .image
        case "mp4", "mov", "mkv", "avi", "m4v", "wmv":
            self = .video
        case "pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "txt", "pages", "numbers":
            self = .document
        case "mp3", "flac", "aac", "wav", "m4a", "ogg":
            self = .audio
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            self = .archive
        default:
            self = .other(ext)
        }
    }

    var symbolName: String {
        switch self {
        case .image:    return "photo"
        case .video:    return "film"
        case .document: return "doc.text"
        case .audio:    return "music.note"
        case .archive:  return "archivebox"
        case .other:    return "doc"
        }
    }

    var displayName: String {
        switch self {
        case .image:       return "Photos"
        case .video:       return "Videos"
        case .document:    return "Documents"
        case .audio:       return "Audio"
        case .archive:     return "Archives"
        case .other(let e): return e.uppercased()
        }
    }
}
