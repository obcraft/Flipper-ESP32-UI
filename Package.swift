// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarauderNative",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MarauderNative", targets: ["MarauderNative"])],
    targets: [
        .target(name: "MarauderCore"),
        .executableTarget(name: "MarauderNative", dependencies: ["MarauderCore"]),
        .executableTarget(name: "MarauderProbe", dependencies: ["MarauderCore"]),
        .executableTarget(name: "MarauderChecks", dependencies: ["MarauderCore"], path: "Tests/MarauderCoreTests")
    ]
)
