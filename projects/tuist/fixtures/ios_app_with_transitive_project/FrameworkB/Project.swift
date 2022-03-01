import ProjectDescription

let project = Project(
    name: "FrameworkB",
    targets: [
        Target(
            name: "FrameworkB-iOS",
            platform: .iOS,
            product: .framework,
            productName: "FrameworkB",
            bundleId: "io.tuist.FrameworkB",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .project(target: "FrameworkC-iOS", path: "../FrameworkC"),
            ]
        ),
        Target(
            name: "FrameworkB-macOS",
            platform: .macOS,
            product: .framework,
            productName: "FrameworkB",
            bundleId: "io.tuist.FrameworkB",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .project(target: "FrameworkC-macOS", path: "../FrameworkC"),
            ]
        ),
    ]
)
