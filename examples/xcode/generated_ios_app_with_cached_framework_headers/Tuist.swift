import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            keepSourceTargets: false,
            profiles: .profiles(
                [
                    "all": .profile(.allPossible),
                ],
                default: .custom("all")
            )
        )
    )
)
