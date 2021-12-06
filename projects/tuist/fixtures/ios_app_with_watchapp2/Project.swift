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
            ]
        ),
    ]
)
