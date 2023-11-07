import ProjectDescription

let project = Project(
    name: "Framework2",
    targets: [
        Target(
            name: "Framework2",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.Framework2",
            infoPlist: "Config/Framework2-Info.plist",
            sources: "Sources/**",
            dependencies: []
        ),

        Target(
            name: "Framework2Tests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework2Tests",
            infoPlist: "Config/Framework2Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework2"),
            ]
        ),
    ]
)
