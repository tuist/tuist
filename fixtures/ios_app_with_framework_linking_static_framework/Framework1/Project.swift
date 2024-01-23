import ProjectDescription

let project = Project(
    name: "Framework1",
    targets: [
        Target(
            name: "Framework1",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework2", path: "../Framework2"),
                .project(target: "Framework3", path: "../Framework3"),
                .project(target: "Framework4", path: "../Framework4"),
            ]
        ),

        Target(
            name: "Framework1Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Config/Framework1Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework1"),
            ]
        ),
    ]
)
