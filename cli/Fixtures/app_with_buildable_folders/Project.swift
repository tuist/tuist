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
                    .exception(excluded: ["App/Sources/Excluded.swift"], compilerFlags: [
                        "App/Sources/WithCompilerFlags.swift": "-print-stats",
                    ]),
                ])),
                "App/Resources",
            ],
            dependencies: []
        ),
    ]
)
