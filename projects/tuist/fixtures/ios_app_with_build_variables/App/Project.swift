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
                // Note there are acceptance tests verifying the first `pre` and last `post` action
                // additions not part of the acceptance test should be added in-between

                // first pre-action
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
