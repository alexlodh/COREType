// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "COREType",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "COREType", targets: ["COREType"])],
    targets: [
        .target(name: "TypingCore"),
        .executableTarget(name: "COREType", dependencies: ["TypingCore"], resources: [.copy("Resources")]),
        .executableTarget(name: "CoreChecks", dependencies: ["TypingCore"], path: "Tests/TypingCoreTests")
    ]
)
