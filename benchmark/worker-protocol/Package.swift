// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VoxInkWorkerProtocol",
    platforms: [.macOS(.v14)],
    products: [.library(name: "VoxInkWorkerProtocol", targets: ["VoxInkWorkerProtocol"])],
    targets: [
        .target(name: "VoxInkWorkerProtocol"),
        .testTarget(name: "VoxInkWorkerProtocolTests", dependencies: ["VoxInkWorkerProtocol"])
    ]
)
