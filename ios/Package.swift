// swift-tools-version: 5.9
//
// Package.swift — lets us unit-test the parser and share-util code WITHOUT
// Xcode, on macOS command line. When Nasser installs Xcode, the main app
// target is created there; this package remains available for quick `swift
// test` sanity runs and CI.
//
// Not-in-this-package: the app target itself (SwiftUI views, GRDB,
// WidgetKit) lives in the Xcode project under ios/Warattil.xcodeproj (to be
// generated on the Mac). Keeping the parser + share util as a pure-Swift
// SPM module means they can be verified on any Linux/macOS Swift toolchain.
//

import PackageDescription

let package = Package(
    name: "WarattilCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "WarattilCore",
            targets: ["WarattilCore"]
        )
    ],
    targets: [
        .target(
            name: "WarattilCore",
            path: "Warattil/Sources",
            exclude: [
                // SwiftUI views live here too; exclude them from the package
                // build since the package has no SwiftUI runtime on Linux.
                "UI",
                "App",
            ],
            resources: [
                .process("../Resources/quran_metadata.xml"),
            ]
        ),
        .testTarget(
            name: "WarattilCoreTests",
            dependencies: ["WarattilCore"],
            path: "WarattilTests",
            resources: [
                .process("Fixtures/page_boundaries.json"),
                .process("Fixtures/juz_boundaries.json"),
            ]
        ),
    ]
)
