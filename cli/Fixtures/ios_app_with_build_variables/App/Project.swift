import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
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
