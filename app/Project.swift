import ProjectDescription

func tuistMenuBarDependencies() -> [TargetDependency] {
    [
        .target(name: "TuistAuthentication"),
        .target(name: "TuistAppStorage"),
        .external(name: "Path"),
        .project(target: "TuistSupport", path: "../"),
        .project(target: "TuistCore", path: "../"),
        .project(target: "TuistServer", path: "../"),
        .project(target: "TuistHTTP", path: "../"),
        .project(target: "TuistAutomation", path: "../"),
        .project(target: "TuistSimulator", path: "../"),
        .external(name: "XcodeGraph"),
        .external(name: "Command"),
        .external(name: "Sparkle"),
        .external(name: "FileSystem"),
        .external(name: "Mockable"),
        .external(name: "Collections"),
        .external(name: "OpenAPIRuntime"),
        .external(name: "FluidMenuBarExtra"),
    ]
}

func inspectBuildPostAction(target: TargetReference) -> ExecutionAction {
    .executionAction(
        title: "Inspect build",
        scriptText: """
        if [ -f "$HOME/.local/bin/mise" ]; then
            eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"
        elif [ -f "$HOME/.local/share/mise/bin/mise" ]; then
            eval "$($HOME/.local/share/mise/bin/mise activate -C $SRCROOT bash --shims)"
        fi

        tuist inspect build
        """,
        target: target
    )
}

func inspectTestPostAction(target: TargetReference) -> ExecutionAction {
    .executionAction(
        title: "Inspect test",
        scriptText: """
        if [ -f "$HOME/.local/bin/mise" ]; then
            eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"
        elif [ -f "$HOME/.local/share/mise/bin/mise" ]; then
            eval "$($HOME/.local/share/mise/bin/mise activate -C $SRCROOT bash --shims)"
        fi

        tuist inspect test
        """,
        target: target
    )
}

let oauthClientIdEnvironmentVariable: EnvironmentVariable =
    switch Environment.env {
    case .string("staging"): "bcb85209-0cef-4acd-8dd4-e0d1c5e5e09a"
    case .string("canary"): "ca49d1d6-acaf-4eaa-b866-774b799044db"
    case .string("development"): "5339abf2-467c-4690-b816-17246ed149d2"
    default: .environmentVariable(value: "", isEnabled: false)
    }
let serverURLEnvironmentVariable: EnvironmentVariable =
    switch Environment.env {
    case .string("staging"): "https://staging.tuist.dev"
    case .string("canary"): "https://canary.tuist.dev"
    case .string("development"): "http://localhost:8080"
    default: .environmentVariable(value: "", isEnabled: false)
    }
let bundleId =
    switch Environment.env {
    case .string("staging"): "dev.tuist.app.staging"
    case .string("canary"): "dev.tuist.app.canary"
    default: "dev.tuist.app"
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
            bundleId: bundleId,
            deploymentTargets: .macOS("15.0.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "Tuist",
                    "CFBundleURLTypes": [
                        Plist.Value.dictionary(
                            [
                                "CFBundleTypeRole": "Viewer",
                                "CFBundleURLName": .string(bundleId),
                                "CFBundleURLSchemes": ["tuist"],
                            ]
                        ),
                    ],
                    "LSUIElement": true,
                    "LSApplicationCategoryType": "public.app-category.developer-tools",
                    "SUPublicEDKey": "XUfguyGrLktmv6E4C/iqfw8p57HWKqx4mJ/hG4/lbMk=",
                    "SUFeedURL":
                        "https://raw.githubusercontent.com/tuist/tuist/main/app/appcast.xml",
                    "CFBundleShortVersionString": "0.24.0",
                    "CFBundleVersion": "3223",
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                    "UISupportedInterfaceOrientations": [
                        "UIInterfaceOrientationPortrait",
                    ],
                ]
            ),
            sources: ["Sources/TuistApp/**"],
            resources: [
                .glob(pattern: "Resources/TuistApp/**", excluding: ["Resources/TuistApp/iOS/**"]),
                .glob(pattern: "Resources/TuistApp/iOS/**", inclusionCondition: .when([.ios])),
            ],
            dependencies: [
                .project(target: "TuistServer", path: "../"),
                .target(name: "TuistAuthentication"),
                .target(name: "TuistNoora", condition: .when([.ios])),
                .target(name: "TuistMenuBar", condition: .when([.macos])),
                .external(name: "FluidMenuBarExtra", condition: .when([.macos])),
                .target(name: "TuistPreviews", condition: .when([.ios])),
                .target(name: "TuistOnboarding", condition: .when([.ios])),
                .target(name: "TuistErrorHandling", condition: .when([.ios])),
                .target(name: "TuistProfile", condition: .when([.ios])),
                .external(name: "ArgumentParser", condition: .when([.ios])),
                .external(name: "TuistSDK"),
            ],
            settings: .settings(
                base: [
                    "DEVELOPMENT_TEAM": "U6LC622NKF",
                    "CODE_SIGN_STYLE": "Automatic",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "CODE_SIGN_ENTITLEMENTS[sdk=iphone*]":
                        "Resources/TuistApp/TuistApp.entitlements",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                ],
                release: [
                    // Needed for the app notarization
                    "OTHER_CODE_SIGN_FLAGS": "--timestamp --deep",
                    "ENABLE_HARDENED_RUNTIME": true,
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphone*]": "Tuist App Ad Hoc",
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]": "Tuist macOS Distribution",
                ]
            )
        ),
        .target(
            name: "TuistPreviews",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.previews",
            deploymentTargets: .iOS("18.0"),
            sources: ["Sources/TuistPreviews/**"],
            dependencies: [
                .project(target: "TuistServer", path: "../"),
                .project(target: "TuistSimulator", path: "../"),
                .target(name: "TuistErrorHandling"),
                .target(name: "TuistNoora"),
                .target(name: "TuistAppStorage"),
                .target(name: "TuistAuthentication"),
                .external(name: "XcodeGraph"),
                .external(name: "NukeUI"),
            ]
        ),
        .target(
            name: "TuistNoora",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.noora",
            deploymentTargets: .iOS("18.0"),
            sources: ["Sources/TuistNoora/**"],
            resources: ["Resources/TuistNoora/**"],
            dependencies: [
                .external(name: "NukeUI"),
            ]
        ),
        .target(
            name: "TuistOnboarding",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.onboarding",
            deploymentTargets: .iOS("18.0"),
            sources: ["Sources/TuistOnboarding/**"],
            dependencies: [
                .project(target: "TuistServer", path: "../"),
                .target(name: "TuistErrorHandling"),
                .target(name: "TuistAuthentication"),
                .target(name: "TuistNoora"),
            ]
        ),
        .target(
            name: "TuistProfile",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.profile",
            deploymentTargets: .iOS("18.0"),
            sources: ["Sources/TuistProfile/**"],
            dependencies: [
                .target(name: "TuistAuthentication"),
                .target(name: "TuistNoora"),
                .target(name: "TuistErrorHandling"),
                .project(target: "TuistServer", path: "../"),
            ]
        ),
        .target(
            name: "TuistErrorHandling",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.error-handling",
            deploymentTargets: .iOS("18.0"),
            sources: ["Sources/TuistErrorHandling/**"],
            dependencies: [
                .project(target: "TuistServer", path: "../"),
                .project(target: "TuistHTTP", path: "../"),
                .external(name: "OpenAPIRuntime"),
            ]
        ),
        .target(
            name: "TuistAppStorage",
            destinations: [.mac, .iPhone],
            product: .staticFramework,
            bundleId: "io.tuist.app-storage",
            deploymentTargets: .multiplatform(iOS: "18.0", macOS: "15.0.0"),
            sources: ["Sources/TuistAppStorage/**"],
            dependencies: [
                .external(name: "Mockable"),
            ]
        ),
        .target(
            name: "TuistAuthentication",
            destinations: [.mac, .iPhone],
            product: .staticFramework,
            bundleId: "io.tuist.authentication",
            deploymentTargets: .multiplatform(iOS: "18.0", macOS: "15.0.0"),
            sources: ["Sources/TuistAuthentication/**"],
            dependencies: [
                .project(target: "TuistServer", path: "../"),
                .target(name: "TuistAppStorage"),
            ]
        ),
        .target(
            name: "TuistMenuBar",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "dev.tuist.menu-bar",
            deploymentTargets: .macOS("15.0.0"),
            sources: ["Sources/TuistMenuBar/**"],
            resources: ["Resources/TuistMenuBar/**"],
            dependencies: tuistMenuBarDependencies()
        ),
        .target(
            name: "TuistMenuBarTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.TuistAppTests",
            deploymentTargets: .macOS("15.0.0"),
            infoPlist: .default,
            sources: ["Tests/TuistMenuBarTests/**"],
            resources: [],
            dependencies: tuistMenuBarDependencies() + [
                .target(name: "TuistMenuBar"),
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
                    inspectBuildPostAction(target: "TuistApp"),
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .targets(
                [
                    .testableTarget(target: "TuistMenuBarTests"),
                ],
                postActions: [
                    inspectTestPostAction(target: "TuistMenuBarTests"),
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
