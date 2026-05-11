// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-alignment-programming",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SwiftAlignmentProgramming",
            targets: ["SwiftAlignmentProgramming"]
        ),
        .executable(
            name: "alignment",
            targets: ["alignment"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.5.0"
        ),
    ],
    targets: [
        .target(
            name: "SwiftAlignmentProgramming",
            path: "Sources/SwiftAlignmentProgramming"
        ),
        .executableTarget(
            name: "alignment",
            dependencies: [
                "SwiftAlignmentProgramming",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/alignment"
        ),
        .testTarget(
            name: "SwiftAlignmentProgrammingTests",
            dependencies: ["SwiftAlignmentProgramming"],
            path: "Tests/SwiftAlignmentProgrammingTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
