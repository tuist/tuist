import ProjectDescription

let project = Project(
    name: "Feature",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "Feature",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Feature",
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "Library", path: .relativeToRoot("Library")),
            ]
        ),
        .target(
            name: "FeatureTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.FeatureTests",
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "Feature"),
                .project(target: "Library", path: .relativeToRoot("Library")),
            ]
        ),
    ]
)
