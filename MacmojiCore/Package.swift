// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacmojiCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MacmojiCore", targets: ["MacmojiCore"])],
    targets: [
        .target(name: "MacmojiCore", resources: [.copy("Resources/emoji.json")]),
        .testTarget(name: "MacmojiCoreTests", dependencies: ["MacmojiCore"]),
    ]
)
