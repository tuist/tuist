import ProjectDescription

let project = Project(
    name: "PreviewsFramework",
    targets: [
        .target(
            name: "PreviewsFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.previewsframework",
            sources: "PreviewsFramework/Sources/**",
            dependencies: [
                .external(name: "ResourcesFramework")
            ]
        ),
    ]
)
