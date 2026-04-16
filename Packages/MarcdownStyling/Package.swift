// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarcdownStyling",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarcdownStyling", targets: ["MarcdownStyling"]),
    ],
    dependencies: [
        // swift-markdown 0.x tags ship with `unsafeFlags` (Windows-only, but
        // SPM blocks the whole product for versioned dependencies). Pin by
        // branch so we can consume it on macOS without the guard tripping.
        .package(url: "https://github.com/apple/swift-markdown", branch: "main"),
    ],
    targets: [
        .target(
            name: "MarcdownStyling",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MarcdownStylingTests",
            dependencies: ["MarcdownStyling"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
