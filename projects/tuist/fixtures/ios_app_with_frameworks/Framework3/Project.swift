import ProjectDescription

let project = Project(
    name: "Framework3",
    targets: [
        Target(
            name: "Framework3",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework3",
            infoPlist: "Config/Framework3-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework4", path: "../Framework4"),
            ]
        ),
    ]
)
