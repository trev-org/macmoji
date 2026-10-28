// swift-tools-version:5.9
// SwiftPM build of the Macmoji app, for machines with only the Command Line Tools (no Xcode).
// Build the .app with scripts/build-app.sh. The XcodeGen project (project.yml) still works too.
import PackageDescription

let package = Package(
    name: "Macmoji",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Macmoji", targets: ["MacmojiApp"])],
    dependencies: [.package(path: "MacmojiCore")],
    targets: [
        .executableTarget(
            name: "MacmojiApp",
            dependencies: [.product(name: "MacmojiCore", package: "MacmojiCore")],
            path: "App/Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
