// swift-tools-version:5.9
//
// Package manifest for Codex/Claude Usage Bar.
//
// The project is split in two SwiftPM targets:
//   * UsageBarCore – pure logic (credential discovery, HTTP, JSON parsing,
//     formatting). No AppKit, so it can be unit tested and reused by CLI tools.
//   * UsageBar     – the actual menu bar app (AppKit + SwiftUI settings window).
//
// `swift build` produces the executable `.build/release/usagebar`; the script
// `scripts/build-app.sh` wraps it into a double-clickable `UsageBar.app`.
//
// Tests live in `Tests/UsageBarCoreTests` and are exposed as an executable
// target (`swift run UsageBarSelfTest`) instead of an XCTest bundle: XCTest ships
// with Xcode, and this project is explicitly buildable with Command Line Tools
// alone. `Tests/UsageBarCoreTests/Harness.swift` is the whole test framework.
//
// Build requirements: macOS 13+, Command Line Tools (Xcode is not required).

import PackageDescription

let package = Package(
    name: "AIUsageBar",
    platforms: [
        // macOS 13 (Ventura) is the floor: SMAppService-free LaunchAgent code
        // path and SwiftUI `Form` are both available there.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "usagebar", targets: ["UsageBar"]),
        .library(name: "UsageBarCore", targets: ["UsageBarCore"])
    ],
    targets: [
        // Each folder carries a README for humans; excluding it keeps SwiftPM
        // from warning about unhandled files on every build.
        .target(
            name: "UsageBarCore",
            path: "Sources/UsageBarCore",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "UsageBar",
            dependencies: ["UsageBarCore"],
            path: "Sources/UsageBar",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "UsageBarSelfTest",
            dependencies: ["UsageBarCore"],
            path: "Tests/UsageBarCoreTests",
            exclude: ["README.md"],
            resources: [
                // JSON fixtures are copied verbatim so tests read them like
                // real API responses instead of inline string literals.
                .copy("Fixtures")
            ]
        )
    ]
)
