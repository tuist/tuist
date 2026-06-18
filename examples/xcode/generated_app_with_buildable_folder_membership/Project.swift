import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // The App target's buildable folder holds its xcconfigs and Info.plist (which must not be duplicated as flat
        // root-level references) and SharedStub.swift, which is also a member of the AppTests target.
        .target(
            name: "App",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.app-with-buildable-folder-membership",
            infoPlist: .file(path: "App/Supporting/App-Info.plist"),
            buildableFolders: [
                .folder("App", exceptions: [
                    .exception(excluded: ["Supporting/App-Info.plist"]),
                    .exception(target: "AppTests", included: ["SharedStub.swift"]),
                ]),
            ],
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", xcconfig: "App/Supporting/Configurations/App-Debug.xcconfig"),
                    .release(name: "Release", xcconfig: "App/Supporting/Configurations/App-Release.xcconfig"),
                ]
            )
        ),
        .target(
            name: "AppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-with-buildable-folder-membership-tests",
            infoPlist: .default,
            buildableFolders: ["AppTests"],
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
