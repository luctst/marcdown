// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MarcdownLaunchKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "MarcdownLaunchKit", targets: ["MarcdownLaunchKit"]),
    ],
    targets: [
        .target(
            name: "MarcdownLaunchKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "MarcdownLaunchKitTests",
            dependencies: ["MarcdownLaunchKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
