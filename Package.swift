// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "naux",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "nauxApp", targets: ["nauxApp"])
    ],
    targets: [
        .executableTarget(
            name: "nauxApp",
            path: "Sources/nauxApp"
        )
    ]
)
