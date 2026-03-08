// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenSnekMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenSnekMac", targets: ["OpenSnekMac"]),
        .executable(name: "OpenSnekProbe", targets: ["OpenSnekProbe"])
    ],
    targets: [
        .executableTarget(
            name: "OpenSnekMac",
            path: "Sources/OpenSnekMac"
        ),
        .executableTarget(
            name: "OpenSnekProbe",
            path: "Sources/OpenSnekProbe"
        ),
        .testTarget(
            name: "OpenSnekMacTests",
            dependencies: ["OpenSnekMac"],
            path: "Tests/OpenSnekMacTests"
        ),
    ]
)
