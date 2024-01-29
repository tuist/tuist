import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Packages/LibraryA"),
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
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
        .target(
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
        .target(
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
        .target(
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
        .target(
            name: "WatchAppUITests",
            platform: .watchOS,
            product: .uiTests,
            bundleId: "io.tuist.App.watchkitapp.uitests",
            dependencies: [.target(name: "WatchApp")]
        ),
    ]
)
