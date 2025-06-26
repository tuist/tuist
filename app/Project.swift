import ProjectDescription

func tuistMenuBarDependencies() -> [TargetDependency] {
    [
        .external(name: "Path", condition: .when([.macos])),
        .project(target: "TuistSupport", path: "../", condition: .when([.macos])),
        .project(target: "TuistCore", path: "../", condition: .when([.macos])),
        .project(target: "TuistServer", path: "../", condition: .when([.macos])),
        .project(target: "TuistAutomation", path: "../", condition: .when([.macos])),
        .external(name: "XcodeGraph", condition: .when([.macos])),
        .external(name: "Command", condition: .when([.macos])),
        .external(name: "Sparkle", condition: .when([.macos])),
        .external(name: "FileSystem", condition: .when([.macos])),
        .external(name: "Mockable", condition: .when([.macos])),
        .external(name: "Collections", condition: .when([.macos])),
        .external(name: "OpenAPIRuntime"),
    ]
}

let inspectBuildPostAction: ExecutionAction = .executionAction(
    title: "Inspect build",
    scriptText: """
    eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

    tuist inspect build
    """
)

let oauthClientIdEnvironmentVariable: EnvironmentVariable = switch Environment.env {
case .string("staging"): "bcb85209-0cef-4acd-8dd4-e0d1c5e5e09a"
case .string("canary"): "ca49d1d6-acaf-4eaa-b866-774b799044db"
case .string("development"): "5339abf2-467c-4690-b816-17246ed149d2"
default: .environmentVariable(value: "", isEnabled: false)
}
let serverURLEnvironmentVariable: EnvironmentVariable = switch Environment.env {
case .string("staging"): "https://staging.tuist.dev"
case .string("canary"): "https://canary.tuist.dev"
case .string("development"): "http://localhost:8080"
default: .environmentVariable(value: "", isEnabled: false)
}

let project = Project(
    name: "TuistApp",
    settings: .settings(
        debug: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MOCKING",
        ]
    ),
    targets: [
        .target(
            name: "TuistApp",
            destinations: [.mac, .iPhone],
            product: .app,
            productName: "Tuist",
            bundleId: "io.tuist.app",
            deploymentTargets: .macOS("14.0.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "Tuist",
                    "CFBundleURLTypes": [
                        Plist.Value.dictionary(
                            [
                                "CFBundleTypeRole": "Viewer",
                                "CFBundleURLName": "io.tuist.app",
                                "CFBundleURLSchemes": ["tuist"],
                            ]
                        ),
                    ],
                    "LSUIElement": true,
                    "LSApplicationCategoryType": "public.app-category.developer-tools",
                    "SUPublicEDKey": "ObyvL/hvYnFyAypkWwYaoeqE/iqB0LK6ioI3SA/Y1+k=",
                    "SUFeedURL":
                        "https://raw.githubusercontent.com/tuist/tuist/main/app/appcast.xml",
                    "CFBundleShortVersionString": "0.10.1",
                    "CFBundleVersion": "0.10.1",
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["Sources/TuistApp/**"],
            resources: ["Resources/TuistApp/**"],
            dependencies: [
                .project(target: "TuistServer", path: "../"),
                .target(name: "TuistMenuBar", condition: .when([.macos])),
                .target(name: "TuistPreviews", condition: .when([.ios])),
                .target(name: "TuistOnboarding", condition: .when([.ios])),
                .target(name: "TuistErrorHandling", condition: .when([.ios])),
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "U6LC622NKF",
                    "CODE_SIGN_STYLE": "Automatic",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                ],
                release: [
                    // Needed for the app notarization
                    "OTHER_CODE_SIGN_FLAGS": "--timestamp --deep",
                    "ENABLE_HARDENED_RUNTIME": true,
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphone*]": "Tuist Ad hoc",
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]": "Tuist macOS Distribution",
                ]
            )
        ),
        .target(
            name: "TuistPreviews",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.previews",
            deploymentTargets: .iOS("18.0"),
            sources: ["Sources/TuistPreviews/**"],
            dependencies: [
                .project(target: "TuistServer", path: "../"),
                .target(name: "TuistErrorHandling"),
            ]
        ),
        .target(
            name: "TuistOnboarding",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.onboarding",
            deploymentTargets: .iOS("18.0"),
            sources: ["Sources/TuistOnboarding/**"],
            dependencies: [
                .project(target: "TuistServer", path: "../"),
                .target(name: "TuistErrorHandling"),
            ]
        ),
        .target(
            name: "TuistErrorHandling",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.error-handling",
            deploymentTargets: .iOS("18.0"),
            sources: ["Sources/TuistErrorHandling/**"],
        ),
        .target(
            name: "TuistMenuBar",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "io.tuist.menu-bar",
            deploymentTargets: .macOS("14.0.0"),
            sources: ["Sources/TuistMenuBar/**"],
            resources: ["Resources/TuistMenuBar/**"],
            dependencies: tuistMenuBarDependencies()
        ),
        .target(
            name: "TuistMenuBarTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.TuistAppTests",
            deploymentTargets: .macOS("14.0.0"),
            infoPlist: .default,
            sources: ["Tests/TuistMenuBarTests/**"],
            resources: [],
            dependencies: tuistMenuBarDependencies() + [
                .target(name: "TuistApp"),
                .project(target: "TuistTesting", path: "../"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "TuistApp",
            buildAction: .buildAction(
                targets: [
                    .target("TuistApp"),
                ],
                postActions: [
                    inspectBuildPostAction,
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .targets(
                [
                    .testableTarget(target: "TuistMenuBarTests"),
                ],
                options: .options(
                    language: "en"
                )
            ),
            runAction: .runAction(
                arguments: .arguments(
                    environmentVariables: [
                        "TUIST_CONFIG_SRCROOT": "$(SRCROOT)",
                        "TUIST_FRAMEWORK_SEARCH_PATHS": "$(FRAMEWORK_SEARCH_PATHS)",
                        "TUIST_OAUTH_CLIENT_ID": oauthClientIdEnvironmentVariable,
                        "TUIST_URL": serverURLEnvironmentVariable,
                    ]
                )
            )
        ),
    ]
)
