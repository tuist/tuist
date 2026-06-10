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
                .target(name: "SharedKMP"),
            ]
        ),
        .kotlinMultiplatform(
            name: "SharedKMP",
            destinations: .iOS,
            gradleProject: "SharedKMP",
            xcframework: .init(
                script: """
                eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"
                gradle assembleSharedKMPReleaseXCFramework
                """,
                path: "SharedKMP/build/XCFrameworks/release/SharedKMP.xcframework"
            ),
            developmentXCFramework: .init(
                script: """
                eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"
                gradle assembleSharedKMPDebugXCFramework
                """,
                path: "SharedKMP/build/XCFrameworks/debug/SharedKMP.xcframework"
            ),
            inputs: [
                .folder("SharedKMP/src"),
                .file("SharedKMP/build.gradle.kts"),
                .file("SharedKMP/settings.gradle.kts"),
                .file("SharedKMP/gradle.properties"),
            ]
        ),
    ]
)
