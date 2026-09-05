import ProjectDescription

let project = Project(
    name: "ExampleLibrary",
    options: .options(
        automaticSchemesOptions: .disabled
    ),
    targets: [
        .target(
            name: "ExampleLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.example-library",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sources/ExampleLibrary/**"]
        ),
        .target(
            name: "ExampleLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.example-library-tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["Tests/ExampleLibraryTests/**"],
            dependencies: [.target(name: "ExampleLibrary")]
        ),
        .target(
            name: "ExampleLibraryApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.example-library-app",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            sources: ["Sources/ExampleLibraryApp/**"],
            dependencies: [.target(name: "ExampleLibrary")]
        ),
    ],
    schemes: [
        .scheme(
            name: "ExampleLibrary",
            shared: true,
            buildAction: .buildAction(
                buildActionTargets: [
                    .target("ExampleLibrary"),
                    .target("ExampleLibraryTests", buildFor: [.testing]),
                    .target(
                        "ExampleLibraryApp",
                        buildFor: [.analyzing, .archiving, .profiling, .running]
                    ),
                ]
            ),
            testAction: .targets(
                ["ExampleLibraryTests"],
                options: .options(language: "en", region: "US")
            ),
            runAction: .runAction(executable: "ExampleLibraryApp")
        ),
    ]
)
