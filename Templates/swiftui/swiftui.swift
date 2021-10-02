import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")
let projectPath = "."
let appPath = "Targets/\(nameAttribute)"
let kitFrameworkPath = "Targets/\(nameAttribute)Kit"
let uiFrameworkPath = "Targets/\(nameAttribute)UI"

func templatePath(_ path: String) -> Path {
    "../\(path)"
}

let template = Template(
    description: "Default template",
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
            path: appPath + "/Sources/AppDelegate.swift",
            templatePath: "AppDelegate.stencil"
        ),
        .file(
            path: appPath + "/Sources/SceneDelegate.swift",
            templatePath: "SceneDelegate.stencil"
        ),
        .file(
            path: appPath + "/Sources/main.swift",
            templatePath: "main.stencil"
        ),
        .file(
            path: appPath + "/Sources/ContentView.swift",
            templatePath: "ContentView.stencil"
        ),
        .file(
            path: appPath + "/Resources/LaunchScreen.storyboard",
            templatePath: templatePath("LaunchScreen+\(platformAttribute).stencil")
        ),
        .file(
            path: appPath + "/Tests/AppTests.swift",
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
            path: uiFrameworkPath + "/Sources/\(nameAttribute)UI.swift",
            templatePath: templatePath("UISource.stencil")
        ),
        .file(
            path: uiFrameworkPath + "/Tests/\(nameAttribute)UITests.swift",
            templatePath: templatePath("/UITests.stencil")
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
