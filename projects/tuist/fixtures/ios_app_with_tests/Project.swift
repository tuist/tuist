import ProjectDescription

let project = Project(
    name: "App",
    options: .options(
        automaticSchemesOptions: .enabled(targetSchemesGrouping: .notGrouped, codeCoverageEnabled: false, testingOptions: [])
    ),
    targets: [
        Target(
            name: "AppCore",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.AppCore",
            deploymentTarget: .iOS(targetVersion: "12.0", devices: .iphone),
            infoPlist: .default,
            sources: .paths([.relativeToManifest("AppCore/Sources/**")])
        ),
        Target(
            name: "AppCoreTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppCoreTests",
            deploymentTarget: .iOS(targetVersion: "12.0", devices: .iphone),
            infoPlist: "Tests.plist",
            sources: "AppCore/Tests/**",
            dependencies: [
                .target(name: "AppCore"),
            ]
        ),
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: .file(path: .relativeToManifest("Info.plist")),
            sources: .paths([.relativeToManifest("App/Sources/**")]),
            dependencies: [
                .target(name: "AppCore"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "",
                "CODE_SIGNING_REQUIRED": "NO",
            ])
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Tests.plist",
            sources: "App/Tests/**",
            dependencies: [
                .target(name: "App"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "",
                "CODE_SIGNING_REQUIRED": "NO",
            ])
        ),
        Target(
            name: "MacFramework",
            platform: .macOS,
            product: .framework,
            bundleId: "io.tuist.MacFramework",
            deploymentTarget: .macOS(targetVersion: "10.15"),
            infoPlist: .file(path: .relativeToManifest("Info.plist")),
            sources: .paths([.relativeToManifest("MacFramework/Sources/**")]),
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "",
                "CODE_SIGNING_REQUIRED": "NO",
            ])
        ),
        Target(
            name: "MacFrameworkTests",
            platform: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.MacFrameworkTests",
            deploymentTarget: .macOS(targetVersion: "10.15"),
            infoPlist: "Tests.plist",
            sources: "MacFramework/Tests/**",
            dependencies: [
                .target(name: "MacFramework"),
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "",
                "CODE_SIGNING_REQUIRED": "NO",
            ])
        ),
        Target(
            name: "AppUITests",
            platform: .iOS,
            product: .uiTests,
            bundleId: "io.tuist.AppUITests",
            infoPlist: "Tests.plist",
            sources: "App/UITests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        Target(
            name: "App-dash",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.AppDash",
            infoPlist: "Info.plist",
            sources: .paths([.relativeToManifest("App/Sources/**")]),
            dependencies: [
                /* Target dependencies can be defined here */
                /* .framework(path: "framework") */
            ],
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "",
                "CODE_SIGNING_REQUIRED": "NO",
            ])
        ),
        Target(
            name: "App-dashUITests",
            platform: .iOS,
            product: .uiTests,
            bundleId: "io.tuist.AppDashUITests",
            infoPlist: "Tests.plist",
            sources: "App/UITests/**",
            dependencies: [
                .target(name: "App-dash"),
            ]
        ),
    ]
)
