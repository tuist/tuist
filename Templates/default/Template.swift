import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")
let projectPath = "."
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
    files: [
        .file(path: "Tuist/ProjectDescriptionHelpers/Project+Templates.swift",
              templatePath: templatePath("Project+Templates.stencil")),
        .file(path: projectPath + "/Project.swift",
              templatePath: templatePath("AppProject.stencil")),
        .file(path: projectPath + "/Sources/AppDelegate.swift",
              templatePath: "AppDelegate.stencil"),
        .file(path: projectPath + "/Tests/AppTests.swift",
              templatePath: templatePath("AppTests.stencil")),
        .file(path: kitFrameworkPath + "/Sources/\(nameAttribute)Kit.swift",
              templatePath: templatePath("/KitSource.stencil")),
        .file(path: uiFrameworkPath + "/Sources/\(nameAttribute)UI.swift",
              templatePath: templatePath("/UISource.stencil")),
        .file(path: ".gitignore",
              templatePath: templatePath("Gitignore.stencil")),
    ]
)
