// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClashVergeWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClashVergeWidgetCore", targets: ["ClashVergeWidgetCore"]),
        .executable(name: "ClashVergeWidgetHost", targets: ["ClashVergeWidgetHost"]),
    ],
    targets: [
        .target(name: "ClashVergeWidgetCore"),
        .executableTarget(
            name: "ClashVergeWidgetHost",
            dependencies: ["ClashVergeWidgetCore"]
        ),
        .testTarget(
            name: "ClashVergeWidgetCoreTests",
            dependencies: ["ClashVergeWidgetCore"]
        ),
    ]
)
