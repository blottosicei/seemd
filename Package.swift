// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "seemd",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "seemd", targets: ["seemd"]),
        .executable(name: "seemd-selftest", targets: ["seemd-selftest"]),
        .library(name: "SeemdCore", targets: ["SeemdCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "SeemdCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Splash", package: "Splash")
            ],
            path: "Sources/SeemdCore"
        ),
        .executableTarget(
            name: "seemd",
            dependencies: [
                "SeemdCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/seemd"
        ),
        .executableTarget(
            name: "seemd-selftest",
            dependencies: ["SeemdCore"],
            path: "Sources/seemd-selftest"
        )
    ]
)
