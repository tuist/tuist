import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
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
