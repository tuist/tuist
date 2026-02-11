import ProjectDescription

let project = Project(
    name: "ForeignBuildApp",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.ForeignBuildApp",
            deploymentTargets: .iOS("17.0"),
            sources: "App/Sources/**",
            dependencies: [
                .target(name: "Framework1"),
            ]
        ),
        .target(
            name: "Framework1",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework1",
            deploymentTargets: .iOS("17.0"),
            sources: "Framework1/Sources/**",
            dependencies: [
                .foreignBuild(
                    name: "SharedKMP",
                    script: """
                        eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"
                        cd $SRCROOT/SharedKMP && gradle assembleSharedKMPReleaseXCFramework
                        """,
                    inputs: [
                        .folder("SharedKMP/src"),
                        .file("SharedKMP/build.gradle.kts"),
                    ],
                    output: .xcframework(path: "SharedKMP/build/XCFrameworks/release/SharedKMP.xcframework", linking: .dynamic)
                ),
            ]
        ),
    ]
)
