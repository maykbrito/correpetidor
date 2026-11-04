// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Correpetidor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CorrepetidorCore"),
        .executableTarget(name: "Correpetidor", dependencies: ["CorrepetidorCore"]),
        .testTarget(name: "CorrepetidorCoreTests", dependencies: ["CorrepetidorCore"]),
    ]
)
