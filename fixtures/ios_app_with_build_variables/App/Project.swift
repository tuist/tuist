import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            scripts: [
                .pre(
                    tool: "/bin/echo",
                    arguments: ["\"tuist\""],
                    name: "Tuist",
                    outputPaths: ["$(DERIVED_FILE_DIR)/output.txt"]
                ),
            ]
        ),
    ]
)
