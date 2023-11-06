import ProjectDescription

let project = Project(
    name: "App",
    options: .options(disableShowEnvironmentVarsInScriptPhases: true),
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            scripts: [
                .pre(tool: "/bin/echo", arguments: ["\"tuist\""], name: "Tuist"),
                .post(tool: "/bin/echo", arguments: ["rocks"], name: "Rocks"),
                .pre(path: "script.sh", name: "Run script"),
            ]
        ),
    ]
)
