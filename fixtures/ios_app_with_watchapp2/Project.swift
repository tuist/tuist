import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Packages/LibraryA"),
    ],
    targets: [
        Target(
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
        Target(
            name: "WatchApp",
            destinations: [.appleWatch],
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
            destinations: [.appleWatch],
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
        Target(
            name: "WatchAppUITests",
            destinations: [.appleWatch],
            product: .uiTests,
            bundleId: "io.tuist.App.watchkitapp.uitests",
            dependencies: [.target(name: "WatchApp")]
        ),
    ]
)
