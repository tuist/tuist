import ProjectDescription

// `Feature` imports `NestedKit`. `FeatureTests` only imports `Feature`, so once `Feature` is a cached binary, the
// tests compile against `NestedKit` only through `Feature`'s Swift module.
let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.App",
            sources: ["App/Sources/**"],
            dependencies: [.target(name: "Feature")]
        ),
        .target(
            name: "Feature",
            destinations: [.mac],
            product: .framework,
            bundleId: "dev.tuist.Feature",
            sources: ["Feature/Sources/**"],
            dependencies: [.external(name: "NestedKit")]
        ),
        .target(
            name: "FeatureTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "dev.tuist.FeatureTests",
            sources: ["FeatureTests/Sources/**"],
            dependencies: [.target(name: "Feature")]
        ),
    ]
)
