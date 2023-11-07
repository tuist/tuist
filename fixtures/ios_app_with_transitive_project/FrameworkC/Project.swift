import ProjectDescription

let project = Project(
    name: "FrameworkC",
    targets: [
        Target(
            name: "FrameworkC-iOS",
            platform: .iOS,
            product: .staticFramework,
            productName: "FrameworkC",
            bundleId: "io.tuist.FrameworkC",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: []
        ),
        Target(
            name: "FrameworkC-macOS",
            platform: .macOS,
            product: .framework,
            productName: "FrameworkC",
            bundleId: "io.tuist.FrameworkC",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: []
        ),
    ]
)
