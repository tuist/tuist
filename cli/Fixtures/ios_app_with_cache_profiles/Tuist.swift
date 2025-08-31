import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            keepSourceTargets: false,
            profiles: .profiles(
                [
                    "development": .profile(base: .onlyExternal, targets: ["ExpensiveModule"]),
                ],
                default: .custom("development")
            )
        )
    )
)
