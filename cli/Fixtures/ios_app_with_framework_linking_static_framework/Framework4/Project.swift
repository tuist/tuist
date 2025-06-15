import ProjectDescription

let project = Project(
    name: "Framework4",
    targets: [
        .target(
            name: "Framework4",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.Framework4",
            infoPlist: "Config/Framework4-Info.plist",
            sources: "Sources/**",
            dependencies: []
        ),

        .target(
            name: "Framework4Tests",
            destinations: .iOS,
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
