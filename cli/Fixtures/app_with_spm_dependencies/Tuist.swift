import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            enforceExplicitDependencies: true
        )
    )
)
