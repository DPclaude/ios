// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Planner",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "PlannerCore", targets: ["PlannerCore"]),
        .library(name: "PlannerStore", targets: ["PlannerStore"])
    ],
    targets: [
        .target(name: "PlannerCore"),
        .testTarget(name: "PlannerCoreTests", dependencies: ["PlannerCore"]),
        .target(name: "PlannerStore", dependencies: ["PlannerCore"]),
        .testTarget(name: "PlannerStoreTests", dependencies: ["PlannerCore", "PlannerStore"])
    ]
)
