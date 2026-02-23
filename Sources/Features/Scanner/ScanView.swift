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
            ProgressView(value: recoveryManager.progressPercent, total: 100)

            HStack {
                Text("\(recoveryManager.filesFound) files found")
                Spacer()
                Text(recoveryManager.currentSpeed)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Button("Cancel", role: .destructive) {
                recoveryManager.cancelRecovery()
            }
        }
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
