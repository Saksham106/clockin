// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClockIn",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClockIn", targets: ["ClockIn"])
    ],
    targets: [
        .executableTarget(
            name: "ClockIn",
            path: "Sources"
        )
    ]
)
