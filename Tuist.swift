import ProjectDescription

let useFastPackageResolution = Environment.useFastPackageResolution.getBoolean(default: false)

let tuist = Tuist(
    fullHandle: "tuist/tuist",
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true,
            disableSandbox: true,
            enableCaching: Environment.enableCaching.getBoolean(default: false)
        ),
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: useFastPackageResolution ? [] : [
                "--replace-scm-with-registry",
            ]
        )
    )
)
