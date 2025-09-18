import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true,
            buildInsightsDisabled: false
        ),
        cacheOptions: .options(keepSourceTargets: true)
    )
)
