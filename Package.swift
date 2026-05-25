// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "netstat",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "netstat", targets: ["netstat"])
    ],
    targets: [
        .executableTarget(
            name: "netstat",
            path: "Sources"
        )
    ]
)
