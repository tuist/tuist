import ProjectDescription

let project = Project(
    name: "assets_example",
    targets: [
        .target(
            name: "assets_example",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.assets-example",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["assets_example/Sources/**"],
            resources: ["assets_example/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "assets_exampleTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.assets-exampleTests",
            infoPlist: .default,
            sources: ["assets_example/Tests/**"],
            resources: [],
            dependencies: [.target(name: "assets_example")]
        ),
    ]
)
