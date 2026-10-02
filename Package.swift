// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FreeShot",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "FreeShot", targets: ["FreeShot"]),
        .library(name: "FreeShotCore", targets: ["FreeShotCore"]),
    ],
    targets: [
        .target(name: "FreeShotCore"),
        .executableTarget(
            name: "FreeShot",
            dependencies: ["FreeShotCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "FreeShotCoreTests", dependencies: ["FreeShotCore"]),
    ],
    swiftLanguageModes: [.v5]
)
