import ProjectDescription

let project = Project(
    name: "B",
    targets: [
        Target(
            name: "B",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.B",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            dependencies: [
                /* Target dependencies can be defined here */
                /* .framework(path: "framework") */
            ]
        ),
        Target(
            name: "BTests",
            platform: .iOS,
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
