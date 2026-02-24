// ScanView.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import SwiftUI

/// Milestone 2.3 + 2.4 placeholder — Scan config & progress UI.
struct ScanView: View {

    let device: StorageDevice
    @EnvironmentObject var recoveryManager: RecoveryManager

    @State private var outputDir: URL = FileManager.default
        .urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HeySOS_Recovered")
    @State private var navigateToResults = false

    var body: some View {
        VStack(spacing: 20) {
            if recoveryManager.isRunning {
                progressSection
            } else if !recoveryManager.recoveredFiles.isEmpty {
                completedSection
            } else {
                configSection
            }

            if let error = recoveryManager.lastError {
                errorBanner(error)
            }

            if !recoveryManager.consoleLog.isEmpty {
                consoleSection
            }
        }
        .padding(24)
        .navigationTitle("Scanning \(device.name)")
        .navigationDestination(isPresented: $navigateToResults) {
            ResultsView()
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private func errorBanner(_ error: RecoveryError) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 6) {
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    if case .insufficientPermissions = error {
                        Button("Open Privacy & Security Settings…") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                            )
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }

                Spacer()
            }
            .padding(4)
        }
    }

    // MARK: - Config

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Output directory ───────────────────────────────────────────
            GroupBox("Output Directory") {
                HStack {
                    Text(outputDir.path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Spacer()
                    Button("Choose…") { chooseOutputDir() }
                }
                .padding(4)
            }

            // ── Scan coverage ──────────────────────────────────────────────
            GroupBox("Scan Coverage") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose how much of the partition to analyse.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Coverage", selection: $recoveryManager.scanOptions.scanWholePartition) {
                        Text("Free space only — faster, finds recently deleted files")
                            .tag(false)
                        Text("Whole partition — thorough, finds older deletions")
                            .tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                .padding(4)
            }

            // ── File type filter ───────────────────────────────────────────
            GroupBox("Recover File Types") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Leave all unchecked to recover every recognised type.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 6) {
                        ForEach(FileTypeCategory.allCases, id: \.self) { cat in
                            Toggle(cat.label, isOn: Binding(
                                get: {
                                    cat.extensions.allSatisfy {
                                        recoveryManager.scanOptions.fileTypeFilter.contains($0)
                                    }
                                },
                                set: { on in
                                    if on {
                                        recoveryManager.scanOptions.fileTypeFilter
                                            .formUnion(cat.extensions)
                                    } else {
                                        recoveryManager.scanOptions.fileTypeFilter
                                            .subtract(cat.extensions)
                                    }
                                }
                            ))
                        }
                    }
                }
                .padding(4)
            }

            // ── Start button ───────────────────────────────────────────────
            Button("Start Deep Scan") {
                Task {
                    await recoveryManager.startRecovery(
                        device: device,
                        outputDir: outputDir
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - File type categories (for the filter UI)

    enum FileTypeCategory: String, CaseIterable {
        case photos, videos, documents, audio, archives

        var label: String {
            switch self {
            case .photos:    return "📷 Photos"
            case .videos:    return "🎬 Videos"
            case .documents: return "📄 Documents"
            case .audio:     return "🎵 Audio"
            case .archives:  return "📦 Archives"
            }
        }

        var extensions: Set<String> {
            switch self {
            case .photos:
                return ["jpg","jpeg","png","raw","cr2","arw","nef","dng","heic","tiff","bmp","gif","webp"]
            case .videos:
                return ["mp4","mov","mkv","avi","m4v","wmv","flv","3gp"]
            case .documents:
                return ["pdf","docx","doc","xlsx","xls","pptx","ppt","txt","pages","numbers","odt","rtf"]
            case .audio:
                return ["mp3","flac","aac","wav","m4a","ogg","opus","aiff"]
            case .archives:
                return ["zip","rar","7z","tar","gz","bz2","xz"]
            }
        }
    }

    // MARK: - Completed

    private var completedSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Recovery Complete")
                .font(.title2.weight(.semibold))

            Text("\(recoveryManager.recoveredFiles.count) files recovered")
                .foregroundStyle(.secondary)

            Button("View Recovered Files") {
                navigateToResults = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Scan Again") {
                recoveryManager.resetRecovery()
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 16) {
            let pct = recoveryManager.progressPercent
            ProgressView(value: pct, total: 100)
                .progressViewStyle(.linear)

            HStack {
                Label("\(recoveryManager.filesFound) files found", systemImage: "doc.fill")
                    .font(.callout)
                Spacer()
                if !recoveryManager.currentSpeed.isEmpty && recoveryManager.currentSpeed != "—" {
                    Text(recoveryManager.currentSpeed)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Text(String(format: "%.1f%%", pct))
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(pct > 0 ? .primary : .secondary)
            }

            if recoveryManager.estimatedSecondsRemaining > 0 {
                let eta = formatDuration(recoveryManager.estimatedSecondsRemaining)
                Text("Estimated time remaining: \(eta)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Cancel", role: .destructive) {
                recoveryManager.cancelRecovery()
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }

    // MARK: - Console Log

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row — rendered outside GroupBox label to avoid macOS
            // hit-testing issues that silently drop button clicks.
            HStack {
                Label("Console Output", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recoveryManager.consoleLog, forType: .string)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            GroupBox {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(recoveryManager.consoleLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .id("logContent")
                    }
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 260)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onChange(of: recoveryManager.consoleLog) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("logContent", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        if panel.runModal() == .OK, let url = panel.url {
            outputDir = url
        }
    }
}
