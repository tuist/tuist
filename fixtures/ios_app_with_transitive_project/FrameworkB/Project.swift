import ProjectDescription

let project = Project(
    name: "FrameworkB",
    targets: [
        .target(
            name: "FrameworkB-iOS",
            destinations: .iOS,
            product: .staticFramework,
            productName: "FrameworkB",
            bundleId: "io.tuist.FrameworkB",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
                .project(target: "FrameworkC-iOS", path: "../FrameworkC"),
            ]
        ),
        .target(
            name: "FrameworkB-macOS",
            destinations: [.mac],
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
