import ProjectDescription

let project = Project(
    name: "FrameworkA",
    targets: [
        .target(
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
        .target(
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
