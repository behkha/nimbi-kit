// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NimbiKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NimbiKit", targets: ["NimbiKit"])
    ],
    targets: [
        .target(name: "NimbiKit", path: "Sources/NimbiKit")
    ]
)
