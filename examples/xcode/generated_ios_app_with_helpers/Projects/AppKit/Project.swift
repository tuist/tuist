import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.framework(name: "AppKit", destinations: .iOS, dependencies: [
    .project(target: "AppSupport", path: "//Projects/AppSupport"),
])
