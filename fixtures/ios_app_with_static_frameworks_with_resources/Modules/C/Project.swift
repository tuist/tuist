import ProjectDescription

let project = Project(
    name: "C",
    targets: [
        .target(
            name: "C",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.C",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            resources: "Resources/**",
            dependencies: [
                /* Target dependencies can be defined here */
                /* .framework(path: "framework") */
                .project(target: "D", path: "../D"),
            ]
        ),
        .target(
            name: "CTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.CTests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "C"),
            ]
        ),
    ]
)
