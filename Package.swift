// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "seemd",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "seemd", targets: ["seemd"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0")
    ],
    targets: [
        .executableTarget(
            name: "seemd",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Splash", package: "Splash")
            ],
            path: "Sources/seemd"
        ),
        .testTarget(
            name: "seemdTests",
            dependencies: ["seemd"],
            path: "Tests/seemdTests"
        )
    ]
)
