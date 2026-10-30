import ProjectDescription

let project = Project(
    name: "RunnersAcceptance",
    targets: [
        .target(
            name: "Core",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.RunnersAcceptance.Core",
            sources: ["Sources/Core/**"]
        ),
        .target(
            name: "Feature",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.RunnersAcceptance.Feature",
            sources: ["Sources/Feature/**"],
            dependencies: [.target(name: "Core")]
        ),
    ]
)
