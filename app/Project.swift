import ProjectDescription

func tuistAppDependencies() -> [TargetDependency] {
    [
        .external(name: "Path"),
        .external(name: "TuistSupport"),
        .external(name: "TuistCore"),
        .external(name: "TuistServer"),
        .external(name: "TuistAutomation"),
        .external(name: "XcodeGraph"),
        .external(name: "Command"),
        .external(name: "Sparkle"),
    ]
}

let project = Project(
    name: "Tuist",
    settings: .settings(
        debug: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MOCKING",
        ]
    ),
    targets: [
        .target(
            name: "Tuist",
            destinations: .macOS,
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTargets: .macOS("14.0.0"),
            infoPlist: .extendingDefault(
                with: [
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
                    "SUFeedURL": "https://raw.githubusercontent.com/tuist/tuist/main/app/appcast.xml",
                    "CFBundleShortVersionString": "0.1.1",
                    "CFBundleVersion": "0.1.1",
                ]
            ),
            sources: ["TuistApp/Sources/**"],
            resources: ["TuistApp/Resources/**"],
            dependencies: tuistAppDependencies(),
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
                ]
            )
        ),
        .target(
            name: "TuistAppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "io.tuist.TuistAppTests",
            deploymentTargets: .macOS("14.0.0"),
            infoPlist: .default,
            sources: ["TuistApp/Tests/**"],
            resources: [],
            dependencies: tuistAppDependencies() + [
                .target(name: "Tuist"),
                .external(name: "TuistSupportTesting"),
                .external(name: "MockableTest"),
            ]
        ),
    ]
)
