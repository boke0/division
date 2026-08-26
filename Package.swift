// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "division",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "division", targets: ["division"]),
        .library(name: "DivisionKit", targets: ["DivisionKit"]),
    ],
    targets: [
        .target(
            name: "DivisionKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "division",
            dependencies: ["DivisionKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DivisionKitTests",
            dependencies: ["DivisionKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
