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
                "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
                "ACTIONS_ID_TOKEN_REQUEST_URL",
                "ACTIONS_ORCHESTRATION_ID",
                "GITHUB_SHA",
                "GITHUB_STATE",
                "GITHUB_TOKEN",
                "GITHUB_WORKFLOW_SHA",
                "RUNNER_NAME",
                "RUNNER_TRACKING_ID",
                "SSH_AUTH_SOCK",
                "TUIST_CACHE_SIGNING_GRANT",
                "TUIST_RUNNER_POD_NAME",
                "TUIST_RUNNER_POD_UID",
            ])
        )
    )
)
