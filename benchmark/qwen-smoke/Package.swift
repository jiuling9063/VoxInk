// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoxInkQwenSmoke",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "voxink-qwen-smoke", targets: ["VoxInkQwenSmoke"]),
    ],
    dependencies: [
        .package(path: "../worker-protocol"),
        .package(
            url: "https://github.com/felixfu824/speech-swift.git",
            revision: "d603472b11c21f5fb6492e9448a04ee669d0bf64"
        ),
        .package(
            url: "https://github.com/ml-explore/mlx-swift",
            exact: "0.31.3"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            exact: "1.3.3"
        ),
    ],
    targets: [
        .target(name: "VoxInkQwenSmokeCore"),
        .executableTarget(
            name: "VoxInkQwenSmoke",
            dependencies: [
                "VoxInkQwenSmokeCore",
                .product(name: "VoxInkWorkerProtocol", package: "worker-protocol"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift"),
            ]
        ),
        .testTarget(
            name: "VoxInkQwenSmokeCoreTests",
            dependencies: ["VoxInkQwenSmokeCore"]
        ),
    ]
)
