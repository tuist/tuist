import ProjectDescription

let project = Project(
    name: "Framework4",
    targets: [
        Target(
            name: "Framework4",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.Framework4",
            infoPlist: "Config/Framework4-Info.plist",
            sources: "Sources/**",
            dependencies: []
        ),

        Target(
            name: "Framework4Tests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework4Tests",
            infoPlist: "Config/Framework4Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework4"),
            ]
        ),
    ]
)
