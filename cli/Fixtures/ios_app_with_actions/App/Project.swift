import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .remote(url: "https://github.com/realm/SwiftLint", requirement: .exact("0.52.4")),
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
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
                    inputPaths: ["Sources/**/*.swift"]
                ),
                .pre(
                    path: "script-with-dependency.sh",
                    name: "PhaseWithDependency",
                    dependencyFile: "$TEMP_DIR/dependencies.d"
                ),
                .post(
                    script: "echo 'Hello World from install build'",
                    name: "Embedded script install build",
                    runForInstallBuildsOnly: true
                ),

                // last post-action
                .post(tool: "/bin/echo", arguments: ["rocks"], name: "Rocks"),
                .pre(path: "script.sh", name: "Run script"),
                .pre(script: "echo 'Hello World'", name: "Embedded script"),
            ],
            dependencies: [
                .package(product: "SwiftLintPlugin", type: .plugin),
            ]
        ),
    ]
)
