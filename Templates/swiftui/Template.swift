import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")
let projectPath = "."
let appPath = "\(nameAttribute)"

func templatePath(_ path: String) -> Path {
    "../\(path)"
}

let template = Template(
    description: "SwiftUI template",
    attributes: [
        nameAttribute,
        platformAttribute,
    ],
    files: [
        .file(
            path: "Tuist/ProjectDescriptionHelpers/Project+Templates.swift",
            templatePath: "Project+Templates.stencil"
        ),
        .file(
            path: projectPath + "/Project.swift",
            templatePath: "AppProject.stencil"
        ),
        .file(
            path: appPath + "/Sources/\(nameAttribute).swift",
            templatePath: "App.stencil"
        ),
        .file(
            path: appPath + "/Sources/ContentView.swift",
            templatePath: "ContentView.stencil"
        ),
        .file(
            path: appPath + "/Tests/AppTests.swift",
            templatePath: templatePath("AppTests.stencil")
        ),
        .file(
            path: appPath + "/Resources/Preview Content/Preview Assets.xcassets/Contents.json",
            templatePath: "Contents.json"
        ),
        .file(
            path: appPath + "/Resources/Assets.xcassets/AccentColor.colorset/Contents.json",
            templatePath: "AccentColorContents.json"
        ),
        .file(
            path: appPath + "/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
            templatePath: "AppIconContents.stencil"
        ),
        .file(
            path: appPath + "/Resources/Assets.xcassets/Contents.json",
            templatePath: "Contents.json"
        ),
        .file(
            path: ".gitignore",
            templatePath: templatePath("Gitignore.stencil")
        ),
    ]
)
