import ProjectDescription

let project = Project(
    name: "AppWithPreviews",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            sources: "App/Sources/**",
            dependencies: [
                .target(name: "PreviewsFramework"),
            ]
        ),
        .target(
            name: "PreviewsFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.previewsframework",
            sources: "PreviewsFramework/Sources/**",
            dependencies: [
                .external(name: "ResourcesFramework"),
            ]
        ),
    ]
)
