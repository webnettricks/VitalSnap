// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VitalSnapCore",
    products: [
        .library(name: "VitalSnapCore", targets: ["VitalSnapCore"]),
    ],
    targets: [
        .target(name: "VitalSnapCore"),
        .testTarget(
            name: "VitalSnapCoreTests",
            dependencies: ["VitalSnapCore"]
        ),
    ]
)
