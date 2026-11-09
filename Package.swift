// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "toneboy",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "toneboy", targets: ["Tonebar"]),
               .executable(name: "toneboy-sandbox-probe", targets: ["SandboxProbe"]),
               .library(name: "AudioDSP", targets: ["AudioDSP"]),
               .library(name: "CaptureVerification", targets: ["CaptureVerification"])],
    targets: [
        .target(name: "AudioDSP", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("CoreAudio")]),
        .target(name: "CaptureVerification"),
        .executableTarget(name: "Tonebar", dependencies: ["AudioDSP", "CaptureVerification"],
                          linkerSettings: [.linkedFramework("Accelerate")]),
        .executableTarget(name: "SandboxProbe", dependencies: ["AudioDSP", "CaptureVerification"]),
        .testTarget(name: "AudioDSPTests", dependencies: ["AudioDSP"]),
        .testTarget(name: "LifecycleTests", dependencies: ["Tonebar"]),
        .testTarget(name: "SelfTestSignalTests", dependencies: ["CaptureVerification"])
    ]
)
