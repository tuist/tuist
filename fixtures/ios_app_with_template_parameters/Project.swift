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
            templateParameters: .assets(
                publicAccess: false,
                name: "MyAssets"
            )
        ),
        .files(
            extensions: ["txt"],
            templateParameters: [
                "publicAccess": false,
                "enumName": "MyFiles",
                "resourceTypeName": "MyFile",
            ]
        ),
        .fonts(
            templateParameters: [
                "publicAccess": false,
                "name": "MyFonts",
            ]
        ),
        // no default template yet
        .json(
            templateParameters: [
                "publicAccess": false,
                "enumName": "MyJSONFiles",
                "forceFileNameEnum": true,
            ]
        ),
        .plists(
            templateParameters: [
                "publicAccess": false,
            ]
        ),
        .strings(
            templateParameters: .strings(
                publicAccess: false,
                name: "MyStrings"
            )
        ),
        // no default template yet
        .yaml(
            templateParameters: [
                "publicAccess": false,
                "enumName": "MyYAMLFiles",
                "forceFileNameEnum": true,
            ]
        ),
    ]
)
