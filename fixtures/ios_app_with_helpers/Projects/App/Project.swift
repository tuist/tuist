import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(name: "App", platform: .iOS, dependencies: [
    .project(target: "AppKit", path: "//Projects/AppKit"),
])
