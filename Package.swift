// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RidgelineOps",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RidgelineCore", targets: ["RidgelineCore"]),
        .library(name: "RidgelineUI", targets: ["RidgelineUI"])
    ],
    targets: [
        .target(name: "RidgelineCore"),
        .target(name: "RidgelineUI", dependencies: ["RidgelineCore"]),
        .testTarget(name: "RidgelineCoreTests", dependencies: ["RidgelineCore"])
    ]
)
