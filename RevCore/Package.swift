// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RevCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RevCore", targets: ["RevCore"])],
    targets: [
        .target(name: "RevCore", resources: [.copy("Resources/emoji.json")]),
        .testTarget(name: "RevCoreTests", dependencies: ["RevCore"]),
    ]
)
