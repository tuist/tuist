import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["Sources/App/**"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
                .target(name: "A"),
                .target(name: "B")
            ]
        ),
        .target(
            name: "A",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.A",
            sources: ["Sources/A/**"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
            ]
        ),
        .target(
            name: "B",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.B",
            sources: ["Sources/B/**"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
            ]
        )
    ]
)
