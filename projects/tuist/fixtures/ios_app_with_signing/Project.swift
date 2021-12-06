import ProjectDescription

let settings: Settings = .settings(base: [
    "PROJECT_BASE": "PROJECT_BASE",
])

let project = Project(
    name: "SignApp",
    settings: settings,
    targets: [
        Target(
            name: "SignApp",
            platform: .iOS,
            product: .app,
            bundleId: "$(PRODUCT_BUNDLE_IDENTIFIER)",
            infoPlist: "Info.plist",
            sources: "App/**",
            dependencies: [],
            settings: .settings(configurations: [
                .debug(name: "Debug", xcconfig: "ConfigurationFiles/Debug.xcconfig"),
                .release(name: "Release", xcconfig: "ConfigurationFiles/Release.xcconfig"),
            ])
        ),
        Target(
            name: "AppA",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.test.appA",
            infoPlist: "Info.plist",
            sources: "App/**",
            dependencies: [],
            settings: .settings(configurations: [
                .debug(name: "Debug", settings: ["PRODUCT_BUNDLE_IDENTIFIER": .string("io.tuist.test.appA")]),
            ])
        ),
        Target(
            name: "AppB",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.test.appB",
            infoPlist: "Info.plist",
            sources: "App/**",
            dependencies: [],
            settings: .settings(configurations: [
                .debug(name: "Debug", settings: ["PRODUCT_BUNDLE_IDENTIFIER": .string("io.tuist.test.appB")]),
            ])
        ),
    ]
)
