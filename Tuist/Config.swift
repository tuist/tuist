import ProjectDescription

let config = Config(
    cloud: .cloud(
        projectId: "tuist/tuist",
        url: "https://cloud.tuist.io",
        options: [.optional]
    ),
    swiftVersion: .init("5.8")
    // TODO: Enable after https://github.com/tuist/tuist/pull/5632 is merged
    // generationOptions: .options(staticSideEffectsWarningTargets: .none)
)
