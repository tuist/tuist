import ProjectDescription

let tuist = Tuist(
    inspectOptions: .options(redundantDependencies: .redundantDependencies(ignoreTagsMatching: ["IgnoreRedundantDependencies"])),
    project: .tuist()
)
