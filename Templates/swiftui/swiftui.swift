import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")
let projectPath = "."
let appPath = "Targets/\(nameAttribute)"
let kitFrameworkPath = "Targets/\(nameAttribute)Kit"
let uiFrameworkPath = "Targets/\(nameAttribute)UI"
let taskPath = "Plugins/\(nameAttribute)"

func templatePath(_ path: String) -> Path {
    "../\(path)"
}

let template = Template(
    description: "SwiftUI template",
    attributes: [
        nameAttribute,
        platformAttribute,
    ],
    items: [
        .file(
            path: "Tuist/ProjectDescriptionHelpers/Project+Templates.swift",
            templatePath: templatePath("Project+Templates.stencil")
        ),
        .file(
            path: projectPath + "/Project.swift",
            templatePath: templatePath("AppProject.stencil")
        ),
        .file(
            path: appPath + "/Sources/\(nameAttribute)App.swift",
            templatePath: "app.stencil"
        ),
        .file(
            path: uiFrameworkPath + "/Sources/ContentView.swift",
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
            templatePath: templatePath("AppTests.stencil")
        ),
        .file(
            path: kitFrameworkPath + "/Sources/\(nameAttribute)Kit.swift",
            templatePath: templatePath("KitSource.stencil")
        ),
        .file(
            path: kitFrameworkPath + "/Tests/\(nameAttribute)KitTests.swift",
            templatePath: templatePath("/KitTests.stencil")
        ),
        .file(
            path: uiFrameworkPath + "/Tests/\(nameAttribute)UITests.swift",
            templatePath: templatePath("/UITests.stencil")
        ),
        .file(
            path: taskPath + "/Sources/tuist-my-cli/main.swift",
            templatePath: templatePath("/main.stencil")
        ),
        .file(
            path: taskPath + "/ProjectDescriptionHelpers/LocalHelper.swift",
            templatePath: templatePath("/LocalHelper.stencil")
        ),
        .file(
            path: taskPath + "/Package.swift",
            templatePath: templatePath("/Package.stencil")
        ),
        .file(
            path: taskPath + "/Plugin.swift",
            templatePath: templatePath("/Plugin.stencil")
        ),
        .file(
            path: ".gitignore",
            templatePath: templatePath("Gitignore.stencil")
        ),
        .file(
            path: "Tuist/Config.swift",
            templatePath: templatePath("Config.stencil")
        ),
    ]
)
