import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            optionalAuthentication: true
        ),
        cacheOptions: .options(
            profiles: .profiles(default: .allPossible)
        )
    )
)
