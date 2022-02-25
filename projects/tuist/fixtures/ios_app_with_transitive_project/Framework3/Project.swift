import ProjectDescription

let project = Project(
    name: "Framework3",
    targets: [
        Target(
            name: "Framework3-iOS",
            platform: .iOS,
            product: .staticFramework,
            productName: "Framework3",
            bundleId: "io.tuist.Framework3",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
            ]
        ),
        Target(
            name: "Framework3-macOS",
            platform: .macOS,
            product: .staticFramework,
            productName: "Framework3",
            bundleId: "io.tuist.Framework3",
            infoPlist: .default,
            sources: "Sources/**",
            dependencies: [
            ]
        ),
    ]
)
