import ProjectDescription

let project = Project(
    name: "FrameworkC",
    targets: [
        Target(
            name: "FrameworkC-iOS",
            destinations: .iOS,
            product: .staticFramework,
            productName: "FrameworkC",
            bundleId: "io.tuist.FrameworkC",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: []
        ),
        Target(
            name: "FrameworkC-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "FrameworkC",
            bundleId: "io.tuist.FrameworkC",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: []
        ),
    ]
)
