// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSnekMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenSnekMac", targets: ["OpenSnekMac"])
    ],
    targets: [
        .executableTarget(
            name: "OpenSnekMac",
            path: "Sources/OpenSnekMac"
        ),
        .testTarget(
            name: "OpenSnekMacTests",
            dependencies: ["OpenSnekMac"],
            path: "Tests/OpenSnekMacTests"
        ),
    ]
)
