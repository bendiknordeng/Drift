// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Drift",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "Drift",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ],
            path: "Sources"
        ),
    ]
)
