import ProjectDescription

let project = Project(
    name: "Framework3",
    targets: [
        .target(
            name: "Framework3",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.Framework3",
            infoPlist: "Config/Framework3-Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework4", path: "../Framework4"),
            ]
        ),

        .target(
            name: "Framework3Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework3Tests",
            infoPlist: "Config/Framework3Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework3"),
            ]
        ),
    ]
)
