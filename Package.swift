// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "toneboy",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "toneboy", targets: ["Tonebar"]),
               .executable(name: "toneboy-sandbox-probe", targets: ["SandboxProbe"])],
    targets: [
        .target(name: "AudioDSP", publicHeadersPath: "include",
                linkerSettings: [.linkedFramework("CoreAudio")]),
        .executableTarget(name: "Tonebar", dependencies: ["AudioDSP"],
                          linkerSettings: [.linkedFramework("Accelerate")]),
        .executableTarget(name: "SandboxProbe", dependencies: ["AudioDSP"]),
        .testTarget(name: "AudioDSPTests", dependencies: ["AudioDSP"]),
        .testTarget(name: "LifecycleTests", dependencies: ["Tonebar"])
    ]
)
