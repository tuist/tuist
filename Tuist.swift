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
                "--replace-scm-with-registry",
            ],
            packageManifestEnvironment: .automatic(excluding: [
                "ACTIONS_*",
                "GITHUB_*",
                "RUNNER_*",
                "SSH_AUTH_SOCK",
                "TUIST_CACHE_SIGNING_GRANT",
                "TUIST_RUNNER_POD_NAME",
                "TUIST_RUNNER_POD_UID",
            ])
        )
    )
)
