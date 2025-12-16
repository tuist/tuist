import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/tuist",
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true,
            disableSandbox: true,
            enableCaching: Environment.enableCaching.getBoolean(default: false)
        ),
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--replace-scm-with-registry"
            ]
        )
    )
)
