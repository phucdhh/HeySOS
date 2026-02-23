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

    var body: some View {
        VStack(spacing: 20) {
            if recoveryManager.isRunning {
                progressSection
            } else {
                configSection
            }
        }
        .padding(24)
        .navigationTitle("Scanning \(device.name)")
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
                    await recoveryManager.startPhotoRecRecovery(
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
                recoveryManager.cancel()
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
