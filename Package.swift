// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhoIsThereCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhoIsThereCore", targets: ["WhoIsThereCore"]),
    ],
    targets: [
        .target(name: "WhoIsThereCore"),
        .testTarget(name: "WhoIsThereCoreTests", dependencies: ["WhoIsThereCore"]),
    ]
)
