// swift-tools-version:6.0
import PackageDescription

// Wisp — a light, fast, secure clipboard bezel for macOS.
//
// Zero third-party dependencies on purpose: the only code that ever touches
// your clipboard is this repo plus Apple's own frameworks. That makes the whole
// thing auditable in an afternoon.
//
// Structure:
//   • WispCore     — all logic + UI (unit-tested)
//   • Wisp         — tiny executable entry point
//   • WispCoreTests — XCTest suite over the privacy filter & history ring
let package = Package(
    name: "Wisp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Wisp", targets: ["Wisp"])
    ],
    targets: [
        .target(
            name: "WispCore",
            path: "Sources/WispCore"
        ),
        .executableTarget(
            name: "Wisp",
            dependencies: ["WispCore"],
            path: "Sources/Wisp"
        ),
        .testTarget(
            name: "WispCoreTests",
            dependencies: ["WispCore"],
            path: "Tests/WispCoreTests"
        )
    ],
    // Pragmatic: Swift 5 language mode keeps the AppKit/Carbon glue free of
    // strict-concurrency churn. Tightening to .v6 is tracked in SECURITY.md.
    swiftLanguageModes: [.v5]
)
