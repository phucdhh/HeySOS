// DeviceSelectorView.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import SwiftUI

/// Milestone 2.2 placeholder — Device list UI.
struct DeviceSelectorView: View {

    @State private var devices: [StorageDevice] = []
    @State private var selectedDevice: StorageDevice?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var navigateToDevice: StorageDevice?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isLoading {
                ProgressView("Scanning for devices...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if devices.isEmpty {
                emptyState
            } else {
                deviceList
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding([.horizontal, .bottom])
            }
        }
        .navigationTitle("Choose a Device")
        .toolbar { toolbarContent }
        .task { await loadDevices() }
        .navigationDestination(item: $navigateToDevice) { device in
            ScanView(device: device)
        }
    }

    // MARK: - Subviews

    private var header: some View {
        Text("Select the storage device you want to recover files from.")
            .foregroundStyle(.secondary)
            .padding()
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Devices Found",
            systemImage: "externaldrive.badge.questionmark",
            description: Text("Connect an SD card, USB drive, or external drive and press Refresh.")
        )
    }

    private var deviceList: some View {
        List {
            ForEach(devices) { device in
                DeviceRow(device: device)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDevice = device
                    }
                    .listRowBackground(
                        selectedDevice == device
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
            }
        }
        .listStyle(.inset)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await loadDevices() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Start Recovery") {
                navigateToDevice = selectedDevice
            }
            .disabled(selectedDevice == nil)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Data

    @MainActor
    private func loadDevices() async {
        isLoading = true
        errorMessage = nil
        do {
            devices = try await Task.detached(priority: .userInitiated) {
                try DiskUtilWrapper.listDevices()
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - DeviceRow

struct DeviceRow: View {
    let device: StorageDevice
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.mediaType.symbolName)
                .font(.title2)
                .foregroundStyle(device.isExternal ? .blue : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    Text(device.id)
                    Text("·")
                    Text(device.fileSystem)
                    if device.isExternal {
                        Text("· External")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(device.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DeviceSelectorView()
        .frame(width: 700, height: 400)
}
