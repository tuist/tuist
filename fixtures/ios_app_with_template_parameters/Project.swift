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
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: .default,
            sources: ["App/Tests/**"],
            resources: [],
            dependencies: [.target(name: "App")]
        ),
    ],
    resourceSynthesizers: [
        .assets(
            templateParameters: [
                "name": "MyAssets",
            ]
        ),
        .files(
            extensions: ["txt"],
            templateParameters: [
                "name": "MyFiles",
            ]
        ),
        .fonts(
            templateParameters: [
                "name": "MyFonts",
            ]
        ),
        .json(
            templateParameters: [
                "name": "MyJSON",
            ]
        ),
        .plists(
            templateParameters: [
                "name": "MyPlist",
            ]
        ),
        .strings(
            templateParameters: [
                "name": "MyStrings",
            ]
        ),
        .yaml(
            templateParameters: [
                "name": "MyYAML",
            ]
        ),
    ]
)
