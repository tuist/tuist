import ProjectDescription

let project = Project(
    name: "Library",
    options: .options(
        automaticSchemesOptions: .disabled
    ),
    targets: [
        .target(
            name: "Library",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.library",
            deploymentTargets: .iOS("16.0"),
            sources: ["Targets/Library/Sources/**"]
        ),
        .target(
            name: "Demo",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.demo",
            deploymentTargets: .iOS("16.0"),
            sources: ["Targets/Demo/Sources/**"],
            dependencies: [.target(name: "Library")]
        ),
        .target(
            name: "LibraryUnitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.library-tests",
            deploymentTargets: .iOS("16.0"),
            sources: ["Targets/Library/Tests/**"],
            dependencies: [.target(name: "Library")],
            metadata: .metadata(tags: ["targets:units"])
        ),
    ],
    schemes: [
        .scheme(
            name: "Library",
            buildAction: .buildAction(targets: ["Library", "Demo"]),
            testAction: .targets(["LibraryUnitTests"]),
            runAction: .runAction(executable: .executable("Demo"))
        ),
    ]
)
