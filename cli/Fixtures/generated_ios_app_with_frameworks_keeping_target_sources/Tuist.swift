import ProjectDescription

let tuist = Tuist(
    fullHandle: "tuist/ios_app_with_frameworks",
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true,
            buildInsightsDisabled: false
        ),
        cacheOptions: .options(keepSourceTargets: true)
    )
)
