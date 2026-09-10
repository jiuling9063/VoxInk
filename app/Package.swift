// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoxInkAppCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "VoxInkCore", targets: ["VoxInkCore"]),
        .executable(name: "voxink-worker-host", targets: ["VoxInkWorkerHost"]),
        .executable(name: "voxink-model-check", targets: ["VoxInkModelCheck"]),
        .executable(name: "VoxInk", targets: ["VoxInkApp"]),
        .executable(name: "voxink-feedback-check", targets: ["VoxInkFeedbackCheck"]),
        .executable(name: "voxink-speech-check", targets: ["VoxInkSpeechCheck"]),
        .executable(name: "voxink-interface-check", targets: ["VoxInkInterfaceCheck"])
    ],
    dependencies: [
        .package(url: "https://github.com/doggy8088/opencc-swift.git", revision: "69fdd9601a7bee4485ea60847910e40744608012")
    ],
    targets: [
        .target(name: "VoxInkCore", dependencies: [.product(name: "OpenCCSwift", package: "opencc-swift")]),
        .target(name: "VoxInkUI", dependencies: ["VoxInkCore"], resources: [.process("Resources")]),
        .executableTarget(name: "VoxInkApp", dependencies: ["VoxInkUI"]),
        .executableTarget(name: "VoxInkFeedbackCheck", dependencies: ["VoxInkUI"]),
        .executableTarget(name: "VoxInkSpeechCheck", dependencies: ["VoxInkCore"]),
        .executableTarget(name: "VoxInkInterfaceCheck", dependencies: ["VoxInkUI"]),
        .testTarget(name: "VoxInkUITests", dependencies: ["VoxInkUI"]),
        .executableTarget(name: "VoxInkWorkerHost", dependencies: ["VoxInkCore"]),
        .executableTarget(name: "VoxInkModelCheck", dependencies: ["VoxInkCore"]),
        .testTarget(
            name: "VoxInkCoreTests",
            dependencies: ["VoxInkCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
