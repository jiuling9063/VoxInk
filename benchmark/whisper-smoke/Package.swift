// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "VoxInkWhisperSmoke", platforms: [.macOS("15.0")],
    products: [.executable(name: "voxink-whisper-smoke", targets: ["VoxInkWhisperSmoke"])],
    dependencies: [
        .package(path: "../worker-protocol"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", revision: "e2adabbe7d98dc4d0ab9a5b75424ecc42a9cdbef"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.1.6")
    ],
    targets: [.executableTarget(name: "VoxInkWhisperSmoke", dependencies: [
        .product(name: "WhisperKit", package: "WhisperKit"),
        .product(name: "VoxInkWorkerProtocol", package: "worker-protocol"),
        .product(name: "Tokenizers", package: "swift-transformers"),
        .product(name: "Hub", package: "swift-transformers")
    ])]
)
