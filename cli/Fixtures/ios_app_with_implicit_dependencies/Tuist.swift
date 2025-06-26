import ProjectDescription

let tuist = Tuist(
    project: .tuist(),
    inspectOptions: .options(redundantDependencies: .redundantDependencies(ignoreTagsMatching: ["IgnoreRedundantDependencies"]))
)
