import ProjectDescription

let project = Project(
    name: "B",
    targets: [
        Target(
            name: "B",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.B",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            resources: "Resources/**",
            dependencies: [
                /* Target dependencies can be defined here */
                /* .framework(path: "framework") */
            ]
        ),
        Target(
            name: "BTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.BTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "B"),
            ]
        ),
    ]
)
