// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "naux",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "nauxApp", targets: ["nauxApp"])
    ],
    targets: [
        .target(
            name: "nauxApp",
            path: "Sources/nauxApp"
        )
    ]
)
