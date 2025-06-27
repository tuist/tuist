import ProjectDescription

let project = Project(
    name: "B",
    targets: [
        .target(
            name: "B",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.B",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            resources: "Resources/**",
            dependencies: [
                // Target dependencies can be defined here
                // .framework(path: "framework")
            ]
        ),
        .target(
            name: "BTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.BTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "B"),
            ]
        ),
    ]
)
