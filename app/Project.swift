import ProjectDescription

func tuistAppDependencies() -> [TargetDependency] {
    [
        .external(name: "Path"),
        .project(target: "TuistSupport", path: "../"),
        .project(target: "TuistCore", path: "../"),
        .project(target: "TuistServer", path: "../"),
        .project(target: "TuistAutomation", path: "../"),
        .external(name: "XcodeGraph"),
        .external(name: "Command"),
        .external(name: "Sparkle"),
        .external(name: "FileSystem"),
        .external(name: "Mockable"),
        .external(name: "Collections"),
        .external(name: "OpenAPIRuntime"),
    ]
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
            destinations: .macOS,
            product: .app,
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
                    "CFBundleShortVersionString": "0.9.0",
                    "CFBundleVersion": "0.9.0",
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
                debug: [
                    "PRODUCT_NAME": "TuistApp",
                ],
                release: [
                    // Needed for the app notarization
                    "OTHER_CODE_SIGN_FLAGS": "--timestamp --deep",
                    "ENABLE_HARDENED_RUNTIME": true,
                    "PRODUCT_NAME": "Tuist",
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
                .target(name: "TuistApp"),
                .project(target: "TuistSupportTesting", path: "../"),
            ]
        ),
    ]
)
