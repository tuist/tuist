import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")
let projectPath = "."
let appPath = "./\(nameAttribute)"
let classNameAttribute: Template.Attribute = .required("class_name")

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
            path: projectPath + "/Tuist/Package.swift",
            templatePath: "Package.stencil"
        ),
        .file(
            path: projectPath + "/Tuist/Config.swift",
            templatePath: "Config.stencil"
        ),
        .file(
            path: appPath + "/Sources/\(classNameAttribute)App.swift",
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
            path: appPath + "/Tests/\(classNameAttribute)Tests.swift",
            templatePath: "AppTests.stencil"
        ),
        .file(
            path: ".gitignore",
            templatePath: "Gitignore.stencil"
        ),
        .file(
            path: ".mise.toml",
            templatePath: "mise.stencil"
        ),
    ]
)
