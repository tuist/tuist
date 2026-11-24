import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.app-with-buildable-folders",
            infoPlist: .default,
            buildableFolders: [
                .folder("App/Sources", exceptions: .exceptions([
                    // Exception paths are relative to the buildable folder.
                    .exception(excluded: ["Excluded.swift"], compilerFlags: [
                        "WithCompilerFlags.swift": "-print-stats",
                    ]),
                ])),
                .folder("App/Resources", exceptions: .exceptions([
                    .exception(platformFilters: [
                        "PlatformSpecific/ios_only.json": [.ios],
                        "PlatformSpecific/tvos_only.json": [.macos],
                    ]),
                ])),
            ],
            dependencies: []
        ),
    ]
)
