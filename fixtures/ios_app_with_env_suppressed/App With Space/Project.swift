import ProjectDescription

let project = Project(
    name: "AppWithSpace",
    options: .options(disableShowEnvironmentVarsInScriptPhases: true),
    targets: [
        .target(
            name: "AppWithSpace",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.app-with-space",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            scripts: [
                .pre(path: "script.sh", name: "Run script"),
            ]
        ),
    ]
)
