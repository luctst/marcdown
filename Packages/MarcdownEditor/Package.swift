// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarcdownEditor",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarcdownEditor", targets: ["MarcdownEditor"]),
    ],
    dependencies: [
        .package(path: "../MarcdownCore"),
        .package(path: "../MarcdownStyling"),
    ],
    targets: [
        .target(
            name: "MarcdownEditor",
            dependencies: [
                "MarcdownCore",
                "MarcdownStyling",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
