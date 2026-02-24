// ContentView.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import SwiftUI

/// Root view — sidebar navigation shell.
struct ContentView: View {

    @StateObject private var recoveryManager = RecoveryManager()

    enum Tab: String, CaseIterable {
        case recoverFiles  = "Recover Files"
        case results       = "Results"
        case fixPartition  = "Fix Partition"
        case history       = "History"
        case consoleLog    = "Console Log"

        var symbolName: String {
            switch self {
            case .recoverFiles:  return "externaldrive.fill.badge.questionmark"
            case .results:       return "doc.on.doc.fill"
            case .fixPartition:  return "wrench.and.screwdriver.fill"
            case .history:       return "clock.fill"
            case .consoleLog:    return "terminal.fill"
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
        // Auto-switch to Results tab as soon as recovered files are enumerated.
        .onChange(of: recoveryManager.recoveredFiles.count) { old, new in
            if old == 0 && new > 0 {
                selectedTab = .results
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(visibleTabs, id: \.self, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.symbolName)
        }
        .listStyle(.sidebar)
        .navigationTitle("HeySOS")
    }

    /// Results and Console Log tabs appear only when there is content.
    private var visibleTabs: [Tab] {
        var tabs: [Tab] = [.recoverFiles]
        if !recoveryManager.recoveredFiles.isEmpty { tabs.append(.results) }
        tabs += [.fixPartition, .history]
        if !recoveryManager.consoleLog.isEmpty    { tabs.append(.consoleLog) }
        return tabs
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
            ContentUnavailableView(
                "Coming in v1.3",
                systemImage: "wrench.and.screwdriver",
                description: Text("Partition recovery via TestDisk will be available in a future release.")
            )
        case .results:
            NavigationStack {
                ResultsView()
            }
        case .history:
            ContentUnavailableView(
                "No History Yet",
                systemImage: "clock",
                description: Text("Previous recovery sessions will appear here.")
            )
        case .consoleLog:
            ConsoleLogView()
        }
    }
}

// MARK: - ConsoleLogView

struct ConsoleLogView: View {
    @EnvironmentObject var recoveryManager: RecoveryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar row
            HStack {
                Text("Console Log")
                    .font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recoveryManager.consoleLog, forType: .string)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(recoveryManager.consoleLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: recoveryManager.consoleLog) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .navigationTitle("Console Log")
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
