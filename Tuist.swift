import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/tuist",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true,
            disableSandbox: true,
            enableCaching: Environment.enableCaching.getBoolean(default: false),
            coverage: .coverage(enabled: true, prefixMapping: true)
        ),
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--replace-scm-with-registry",
            ],
            packageManifestEnvironment: .automatic
        )
    )
)
