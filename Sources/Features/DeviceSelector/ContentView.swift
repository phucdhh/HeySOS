// ContentView.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import SwiftUI

/// Root view — sidebar navigation shell.
/// Milestone 2.1 placeholder.
struct ContentView: View {

    @StateObject private var recoveryManager = RecoveryManager()

    enum Tab: String, CaseIterable {
        case recoverFiles  = "Recover Files"
        case fixPartition  = "Fix Partition"
        case history       = "History"

        var symbolName: String {
            switch self {
            case .recoverFiles:  return "externaldrive.fill.badge.questionmark"
            case .fixPartition:  return "wrench.and.screwdriver.fill"
            case .history:       return "clock.fill"
            }
        }
    }

    @State private var selectedTab: Tab = .recoverFiles

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .environmentObject(recoveryManager)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(Tab.allCases, id: \.self, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.symbolName)
        }
        .listStyle(.sidebar)
        .navigationTitle("HeySOS")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .recoverFiles:
            NavigationStack {
                DeviceSelectorView()
            }
        case .fixPartition:
            // TODO (v1.3): TestDisk UI
            ContentUnavailableView(
                "Coming in v1.3",
                systemImage: "wrench.and.screwdriver",
                description: Text("Partition recovery via TestDisk will be available in a future release.")
            )
        case .history:
            // TODO (v1.2): Scan history
            ContentUnavailableView(
                "No History Yet",
                systemImage: "clock",
                description: Text("Previous recovery sessions will appear here.")
            )
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
