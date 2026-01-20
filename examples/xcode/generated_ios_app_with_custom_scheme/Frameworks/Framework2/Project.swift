import ProjectDescription

let project = Project(
    name: "Framework2",
    targets: [
        .target(
            name: "Framework2",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework2",
            infoPlist: "Config/Framework2-Info.plist",
            sources: "Sources/**",
            dependencies: []
        ),

        .target(
            name: "Framework2Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.Framework2Tests",
            infoPlist: "Config/Framework2Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework2"),
            ]
        ),
    ]
)
