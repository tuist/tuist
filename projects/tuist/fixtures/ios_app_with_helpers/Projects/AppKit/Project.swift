import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(name: "AppKit", platform: .iOS, dependencies: [
    .project(target: "AppSupport", path: "//Projects/AppSupport"),
])
