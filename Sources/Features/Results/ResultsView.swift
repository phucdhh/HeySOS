// ResultsView.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import SwiftUI

/// Milestone 2.5 placeholder — Grid/List of recovered files.
struct ResultsView: View {

    @EnvironmentObject var recoveryManager: RecoveryManager
    @State private var searchText = ""
    @State private var filterType: FileType? = nil

    private var displayedFiles: [RecoveredFile] {
        recoveryManager.recoveredFiles.filter { file in
            (filterType == nil || file.fileType == filterType) &&
            (searchText.isEmpty ||
             file.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        Group {
            if recoveryManager.recoveredFiles.isEmpty {
                ContentUnavailableView(
                    "No Files Recovered Yet",
                    systemImage: "doc.questionmark",
                    description: Text("Start a scan to recover deleted files.")
                )
            } else {
                fileGrid
            }
        }
        .searchable(text: $searchText, prompt: "Search files…")
        .navigationTitle("Recovered Files (\(recoveryManager.recoveredFiles.count))")
        .toolbar { toolbarContent }
    }

    // MARK: - Grid

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160))]

    private var fileGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(displayedFiles) { file in
                    FileCell(file: file)
                }
            }
            .padding()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Save All") {
                // TODO: Copy all files to user-chosen destination
            }
            .disabled(recoveryManager.recoveredFiles.isEmpty)
        }
    }
}

// MARK: - FileCell

struct FileCell: View {
    let file: RecoveredFile

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: file.fileType.symbolName)
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text(file.name)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(file.formattedSize)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(file.fileURL.path, inFileViewerRootedAtPath: "")
            }
        }
    }
}
