// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HistoryClipboard",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "HistoryClipboard",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/HistoryClipboard"
        ),
        .testTarget(
            name: "HistoryClipboardTests",
            dependencies: ["HistoryClipboard"],
            path: "Tests/HistoryClipboardTests"
        )
    ]
)
