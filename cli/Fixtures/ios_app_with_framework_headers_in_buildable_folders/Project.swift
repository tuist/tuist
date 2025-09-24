import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ]
                ]
            ),
            buildableFolders: [
                "App/Sources",
                "App/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.Framework",
            buildableFolders: [
                "Framework/Resources",
                "Framework/Sources",
            ]
        ),
        .target(
            name: "TuistAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.TuistAppTests",
            infoPlist: .default,
            buildableFolders: [
                "App/Tests"
            ],
            dependencies: [.target(name: "App")]
        ),
    ]
)
