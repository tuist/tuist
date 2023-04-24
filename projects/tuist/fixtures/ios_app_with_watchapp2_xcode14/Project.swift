import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Packages/LibraryA"),
    ],
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Support/App-Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyFramework.framework")
                .target(name: "WatchApp"),
                .package(product: "LibraryA"),
            ]
        ),
        Target(
            name: "WatchApp",
            platform: .watchOS,
            product: .watch2App,
            bundleId: "io.tuist.App.watchkitapp",
            infoPlist: .default,
            resources: "WatchApp/**",
            dependencies: [
                .target(name: "WatchAppExtension"),
            ]
        ),
        Target(
            name: "WatchAppExtension",
            platform: .watchOS,
            product: .watch2Extension,
            bundleId: "io.tuist.App.watchkitapp.watchkitextension",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "WatchApp Extension",
            ]),
            sources: ["WatchAppExtension/**"],
            resources: ["WatchAppExtension/**/*.xcassets"],
            dependencies: [
                .package(product: "LibraryA"),
                .target(name: "WatchAppWidgetExtension"),
            ]
        ),
        Target(
            name: "WatchAppWidgetExtension",
            platform: .watchOS,
            product: .appExtension,
            bundleId: "io.tuist.App.watchkitapp.watchkitextension.WatchAppWidget",
            infoPlist: .extendingDefault(with: [
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: ["WatchAppWidgetExtension/**"],
            resources: ["WatchAppWidgetExtension/**/*.xcassets"],
            dependencies: [
                .sdk(name: "WidgetKit", type: .framework, status: .required),
                .sdk(name: "SwiftUI", type: .framework, status: .required),
            ]
        ),
        Target(
            name: "WatchAppUITests",
            platform: .watchOS,
            product: .uiTests,
            bundleId: "io.tuist.App.watchkitapp.uitests",
            dependencies: [.target(name: "WatchApp")]
        ),
    ]
)
