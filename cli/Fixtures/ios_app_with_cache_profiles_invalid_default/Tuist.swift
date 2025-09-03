import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            keepSourceTargets: false,
            profiles: .profiles(
                [
                    "development": .profile(
                        base: .onlyExternal,
                        targets: [
                            "ExpensiveModule",
                            "tag:cacheable",
                        ]
                    ),
                ],
                // Intentionally invalid default referencing a non-existent profile
                default: .custom("missing")
            )
        )
    )
)
