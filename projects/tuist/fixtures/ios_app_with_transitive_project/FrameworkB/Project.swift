import ProjectDescription

let project = Project(
    name: "FrameworkB",
    targets: [
        Target(
            name: "FrameworkB-iOS",
            platform: .iOS,
            product: .staticFramework,
            productName: "FrameworkB",
            bundleId: "io.tuist.FrameworkB",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
            ]
        ),
        Target(
            name: "FrameworkB-macOS",
            platform: .macOS,
            product: .staticFramework,
            productName: "FrameworkB",
            bundleId: "io.tuist.FrameworkB",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
            ]
        ),
    ]
)
