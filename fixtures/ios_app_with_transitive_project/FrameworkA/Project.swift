import ProjectDescription

let project = Project(
    name: "FrameworkA",
    targets: [
        Target(
            name: "FrameworkA-iOS",
            destinations: .iOS,
            product: .staticFramework,
            productName: "FrameworkA",
            bundleId: "io.tuist.FrameworkA",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .project(target: "FrameworkB-iOS", path: "../FrameworkB"),
            ]
        ),
        Target(
            name: "FrameworkA-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "FrameworkA",
            bundleId: "io.tuist.FrameworkA",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .project(target: "FrameworkB-macOS", path: "../FrameworkB"),
            ]
        ),
    ]
)
