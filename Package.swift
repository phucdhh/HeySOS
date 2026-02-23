// swift-tools-version: 5.9
// Package.swift — HeySOS Core (non-UI, testable via `swift test`)
//
// This package mirrors the Xcode target's Core + Models sources so we can
// run unit tests without full Xcode. The SwiftUI views live only in the
// Xcode target and are excluded here.

import PackageDescription

let package = Package(
    name: "HeySOS",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HeySOSCore", targets: ["HeySOSCore"])
    ],
    targets: [

        // Core + Models — all non-UI Swift files
        .target(
            name: "HeySOSCore",
            path: "Sources",
            exclude: [
                // SwiftUI views — require Xcode, excluded from SPM build
                "App",
                "Features",
                "Resources",
            ],
            sources: [
                "Core",
                "Models",
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
            ]
        ),

        // Unit tests
        .testTarget(
            name: "HeySOSTests",
            dependencies: ["HeySOSCore"],
            path: "Tests",
            sources: [
                "LogParserTests",
                "RecoveryManagerTests",
            ]
        ),
    ]
)
