// swift-tools-version:5.9
// SwiftPM build of the Rev app, for machines with only the Command Line Tools (no Xcode).
// Build the .app with scripts/build-app.sh. The XcodeGen project (project.yml) still works too.
import PackageDescription

let package = Package(
    name: "Rev",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Rev", targets: ["RevApp"])],
    dependencies: [.package(path: "RevCore")],
    targets: [
        .executableTarget(
            name: "RevApp",
            dependencies: [.product(name: "RevCore", package: "RevCore")],
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
