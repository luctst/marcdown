// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarcdownCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarcdownCore", targets: ["MarcdownCore"]),
    ],
    targets: [
        .target(
            name: "MarcdownCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MarcdownCoreTests",
            dependencies: ["MarcdownCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
