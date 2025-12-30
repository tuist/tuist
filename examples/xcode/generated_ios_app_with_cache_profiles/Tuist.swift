import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            keepSourceTargets: false,
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: [
                            "ExpensiveModule",
                            "tag:cacheable",
                        ]
                    ),
                ],
                default: "development"
            )
        )
    )
)
