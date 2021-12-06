import ProjectDescription

let project = Project(
    name: "Framework4",
    targets: [
        Target(
            name: "Framework4",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework4",
            infoPlist: "Config/Framework4-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework5", path: "../Framework5"),
            ]
        ),
    ]
)
