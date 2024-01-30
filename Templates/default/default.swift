import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")
let projectPath = "."
let appPath = "./\(nameAttribute)"

let template = Template(
    description: "Default template",
    attributes: [
        nameAttribute,
        platformAttribute,
    ],
    items: [
        .file(
            path: projectPath + "/Project.swift",
            templatePath: "AppProject.stencil"
        ),
        .file(
            path: appPath + "/Sources/\(nameAttribute)App.swift",
            templatePath: "app.stencil"
        ),
        .file(
            path: appPath + "/Sources/ContentView.swift",
            templatePath: "ContentView.stencil"
        ),
        .directory(
            path: appPath + "/Resources",
            sourcePath: "\(platformAttribute)/Assets.xcassets"
        ),
        .directory(
            path: appPath + "/Resources",
            sourcePath: "Preview Content"
        ),
        .file(
            path: appPath + "/Tests/\(nameAttribute)Tests.swift",
            templatePath: "AppTests.stencil"
        ),
        .file(
            path: ".gitignore",
            templatePath: "Gitignore.stencil"
        ),
        .file(
            path: appPath + "/Resources/LaunchScreen.storyboard",
            templatePath: "LaunchScreen+\(platformAttribute).stencil"
        ),
    ]
)
