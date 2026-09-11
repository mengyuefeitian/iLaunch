// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "iLaunch",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "iLaunch", targets: ["iLaunch"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "iLaunch",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/iLaunch",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "iLaunchTests",
            dependencies: ["iLaunch"],
            path: "Tests/iLaunchTests"
        )
    ]
)
