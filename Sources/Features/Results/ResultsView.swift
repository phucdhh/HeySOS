// ResultsView.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import SwiftUI
import QuickLookUI

// MARK: - Quick Look coordinator

/// Bridges SwiftUI to the AppKit QLPreviewPanel.
/// We set ourselves directly as the panel's dataSource rather than relying
/// on the responder chain, which is simpler in a SwiftUI app.
final class QLCoordinator: NSObject, ObservableObject, QLPreviewPanelDataSource {

    var previewURLs: [URL] = []

    // MARK: QLPreviewPanelDataSource
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs[index] as NSURL
    }

    func preview(_ urls: [URL]) {
        previewURLs = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }
}

// MARK: - ResultsView

struct ResultsView: View {

    @EnvironmentObject var recoveryManager: RecoveryManager
    @StateObject private var ql = QLCoordinator()

    @State private var searchText       = ""
    @State private var filterType: FileType? = nil
    @State private var sortOrder        = SortOrder.nameAscending
    @State private var selectedFileID: UUID? = nil

    // MARK: - Computed

    private var displayedFiles: [RecoveredFile] {
        recoveryManager.recoveredFiles
            .filter { file in
                (filterType == nil || file.fileType == filterType) &&
                (searchText.isEmpty ||
                 file.name.localizedCaseInsensitiveContains(searchText))
            }
            .sorted(by: sortOrder.comparator)
    }

    // MARK: - Body

    var body: some View {
        Group {
            if recoveryManager.recoveredFiles.isEmpty {
                ContentUnavailableView(
                    "No Files Recovered Yet",
                    systemImage: "doc.questionmark",
                    description: Text("Start a scan to recover deleted files.")
                )
            } else {
                fileTable
            }
        }
        .searchable(text: $searchText, prompt: "Search files…")
        .navigationTitle("Recovered Files (\(recoveryManager.recoveredFiles.count))")
        .toolbar { toolbarContent }
    }

    // MARK: - Table

    private var fileTable: some View {
        Table(displayedFiles, selection: $selectedFileID) {
            TableColumn("Name") { file in
                HStack(spacing: 8) {
                    Image(systemName: file.fileType.symbolName)
                        .foregroundStyle(.blue)
                        .frame(width: 20)
                    Text(file.name)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .contextMenu { contextMenu(for: file) }
            }
            .width(min: 200)

            TableColumn("Type") { file in
                Text(file.fileExtension.isEmpty ? "—" : file.fileExtension.uppercased())
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .width(60)

            TableColumn("Size") { file in
                Text(file.formattedSize)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .width(90)

            TableColumn("Recovered") { file in
                Text(file.recoveredAt, style: .date)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .width(100)
        }
        .focusable()
        .onKeyPress(.space) {
            triggerQuickLook()
            return .handled
        }
        .onChange(of: selectedFileID) { _, _ in
            if QLPreviewPanel.sharedPreviewPanelExists(),
               let panel = QLPreviewPanel.shared(), panel.isVisible {
                triggerQuickLook()
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for file: RecoveredFile) -> some View {
        Button("Open in Finder") {
            NSWorkspace.shared.selectFile(file.fileURL.path,
                                          inFileViewerRootedAtPath: "")
        }
        Button("Quick Look") {
            selectedFileID = file.id
            ql.preview([file.fileURL])
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.fileURL.path, forType: .string)
        }
    }

    // MARK: - Quick Look trigger

    private func triggerQuickLook() {
        guard let id = selectedFileID,
              let file = recoveryManager.recoveredFiles.first(where: { $0.id == id })
        else { return }
        ql.preview([file.fileURL])
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Filter", selection: $filterType) {
                Text("All Types").tag(Optional<FileType>.none)
                Divider()
                Text("Photos").tag(Optional(FileType.image))
                Text("Videos").tag(Optional(FileType.video))
                Text("Documents").tag(Optional(FileType.document))
                Text("Audio").tag(Optional(FileType.audio))
                Text("Archives").tag(Optional(FileType.archive))
            }
            .pickerStyle(.menu)
            .fixedSize()
        }

        ToolbarItem(placement: .primaryAction) {
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }

        ToolbarItem(placement: .status) {
            Text("Select a file · Space to preview · Right-click for options")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - SpaceBar handler (NSEvent local monitor)

/// Invisible NSViewRepresentable that installs a local key-down monitor.
/// Calls `onSpace` whenever the space bar is pressed while the window is key.
struct SpaceBarHandler: NSViewRepresentable {
    let onSpace: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 49 { // space bar
                self.onSpace()
                return nil // consume the event
            }
            return event
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }

    final class Coordinator {
        var monitor: Any?
    }
}

// MARK: - Sort order

enum SortOrder: String, CaseIterable {
    case nameAscending, nameDescending, sizeDescending, dateDescending

    var label: String {
        switch self {
        case .nameAscending:  return "Name A→Z"
        case .nameDescending: return "Name Z→A"
        case .sizeDescending: return "Largest First"
        case .dateDescending: return "Newest First"
        }
    }

    var comparator: (RecoveredFile, RecoveredFile) -> Bool {
        switch self {
        case .nameAscending:  return { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameDescending: return { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .sizeDescending: return { $0.size > $1.size }
        case .dateDescending: return { $0.recoveredAt > $1.recoveredAt }
        }
    }
}
