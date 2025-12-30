import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.app(name: "App", destinations: .iOS, dependencies: [
    .project(target: "AppKit", path: "//Projects/AppKit"),
])
