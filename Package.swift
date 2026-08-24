// swift-tools-version: 6.3
import PackageDescription

// The Flight CLI.
//
// `templates/` holds complete, CI-verified projects, and they are embedded in
// this binary rather than read from disk at run time: an installed CLI has no
// repository to read from. `Sources/flight/EmbeddedTemplates.swift` is
// generated from those directories by CI/generate-embedded-templates.sh, and
// CI fails if it has drifted from them.
let package = Package(
    name: "flight-cli",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "flight", targets: ["flight"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "flight",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .testTarget(name: "flightTests", dependencies: ["flight"]),
    ]
)
