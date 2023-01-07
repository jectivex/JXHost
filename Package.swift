// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "JXHost",
    platforms: [ .macOS(.v12), .iOS(.v15), .tvOS(.v15) ],
    products: [
        .library(name: "JXHost", targets: ["JXHost"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jectivex/JXPod.git", from: "0.3.6"),
        .package(url: "https://github.com/jectivex/JXBridge.git", from: "0.1.14"),
        .package(url: "https://github.com/fair-ground/Fair.git", from: "0.8.26"),
    ],
    targets: [
        .target(
            name: "JXHost",
            dependencies: [
                .product(name: "JXPod", package: "JXPod"),
                .product(name: "JXBridge", package: "JXBridge"),
                .product(name: "FairApp", package: "Fair"),
            ],
            resources: [.process("Resources")]),
        .testTarget(
            name: "JXHostTests",
            dependencies: ["JXHost"],
            resources: [.copy("TestResources")]),
    ]
)
