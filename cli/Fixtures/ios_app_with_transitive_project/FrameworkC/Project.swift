import ProjectDescription

let project = Project(
    name: "FrameworkC",
    targets: [
        .target(
            name: "FrameworkC-iOS",
            destinations: .iOS,
            product: .staticFramework,
            productName: "FrameworkC",
            bundleId: "dev.tuist.FrameworkC",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: []
        ),
        .target(
            name: "FrameworkC-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "FrameworkC",
            bundleId: "dev.tuist.FrameworkC",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: []
        ),
    ]
)
