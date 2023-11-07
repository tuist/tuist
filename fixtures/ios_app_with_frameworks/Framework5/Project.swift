import ProjectDescription

let project = Project(
    name: "Framework5",
    targets: [
        Target(
            name: "Framework5",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework5",
            infoPlist: "Config/Framework5-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .sdk(name: "ARKit", type: .framework),
            ]
        ),
    ]
)
