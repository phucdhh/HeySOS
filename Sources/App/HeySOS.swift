// HeySOS.swift
// HeySOS — Free & Open-Source Data Recovery for macOS
// Copyright (C) 2026 HeySOS Contributors — GPLv3

import SwiftUI

@main
struct HeySOS: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // TODO: Add menu commands (Phase 2)
        }
    }
}
