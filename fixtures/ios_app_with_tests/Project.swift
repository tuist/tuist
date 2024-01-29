import ProjectDescription

let project = Project(
    name: "App",
    options: .options(
        automaticSchemesOptions: .enabled(
            targetSchemesGrouping: .notGrouped,
            codeCoverageEnabled: false,
            testingOptions: [],
            testScreenCaptureFormat: .screenshots
        )
    ),
    targets: [
        .target(
            name: "AppCore",
            destinations: [.iPhone],
            product: .framework,
            bundleId: "io.tuist.AppCore",
            deploymentTargets: .iOS("12.0"),
            infoPlist: .default,
            sources: .paths([.relativeToManifest("AppCore/Sources/**")])
        ),
        .target(
            name: "AppCoreTests",
            destinations: [.iPhone],
            product: .unitTests,
            bundleId: "io.tuist.AppCoreTests",
            deploymentTargets: .iOS("12.0"),
            infoPlist: "Tests.plist",
            sources: "AppCore/Tests/**",
            dependencies: [
                .target(name: "AppCore"),
            ]
        ),
        .target(
            name: "App",
            destinations: .iOS,
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
        .target(
            name: "AppTests",
            destinations: .iOS,
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
        .target(
            name: "MacFramework",
            destinations: [.mac],
            product: .framework,
            bundleId: "io.tuist.MacFramework",
            deploymentTargets: .macOS("10.15"),
            infoPlist: .file(path: .relativeToManifest("Info.plist")),
            sources: .paths([.relativeToManifest("MacFramework/Sources/**")]),
            settings: .settings(base: [
                "CODE_SIGN_IDENTITY": "",
                "CODE_SIGNING_REQUIRED": "NO",
            ])
        ),
        .target(
            name: "MacFrameworkTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "io.tuist.MacFrameworkTests",
            deploymentTargets: .macOS("10.15"),
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
        .target(
            name: "AppUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "io.tuist.AppUITests",
            infoPlist: "Tests.plist",
            sources: "App/UITests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
        .target(
            name: "App-dash",
            destinations: .iOS,
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
        .target(
            name: "App-dashUITests",
            destinations: .iOS,
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
