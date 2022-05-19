// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "EarlGrey",
    products: [
        .library(
            name: "EarlGrey",
            targets: ["EarlGrey"]),
    ],
    targets: [
        .target(
            name: "EarlGrey",
            dependencies: [],
            path: "AppFramework"),
        .testTarget(
            name: "Tests",
            dependencies: ["EarlGrey"],
            path: "TestLib"),
    ]
)