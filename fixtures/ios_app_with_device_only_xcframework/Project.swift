import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "MyTarget",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.MyTarget",
            infoPlist: .default,
            sources: [
                "MyTarget/Sources/**",
            ],
            dependencies: [
                .target(name: "Lib"),
            ]
        ),
        Target(
            name: "Lib",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Lib",
            infoPlist: .default,
            sources: [
                "Lib/Sources/**",
            ]
        ),
    ]
)
