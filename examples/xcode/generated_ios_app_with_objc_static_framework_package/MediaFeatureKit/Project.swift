import ProjectDescription

let project = Project(
    name: "MediaFeatureKit",
    targets: [
        .target(
            name: "MediaFeatureKit",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.MediaFeatureKit",
            deploymentTargets: .iOS("16.0"),
            sources: "Sources/**",
            dependencies: [
                .external(name: "ObjCPlayerSupport"),
            ]
        ),
    ]
)
