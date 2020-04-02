import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")

let projectsPath = "Projects"
let appPath = projectsPath + "/\(nameAttribute)"
let kitFrameworkPath = projectsPath + "/\(nameAttribute)Kit"
let supportFrameworkPath = projectsPath + "/\(nameAttribute)Support"

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
        .file(path: "Setup.swift",
              templatePath: templatePath("Setup.stencil")),
        .file(path: "Workspace.swift",
              templatePath: templatePath("Workspace.stencil")),
        .file(path: "Tuist/ProjectDescriptionHelpers/Project+Templates.swift",
              templatePath: "Project+Templates.stencil"),
        .file(path: appPath + "/Project.swift",
              templatePath: templatePath("AppProject.stencil")),
        .file(path: kitFrameworkPath + "/Project.swift",
              templatePath: templatePath("KitFrameworkProject.stencil")),
        .file(path: supportFrameworkPath + "/Project.swift",
              templatePath: templatePath("SupportFrameworkProject.stencil")),
        .file(path: appPath + "/Sources/AppDelegate.swift",
              templatePath: "AppDelegate.stencil"),
        .file(path: appPath + "/Tests/\(nameAttribute)Tests.swift",
              templatePath: templatePath("Tests.stencil")),
        .file(path: kitFrameworkPath + "/Sources/\(nameAttribute)Kit.swift",
              templatePath: templatePath("KitSource.stencil")),
        .file(path: kitFrameworkPath + "/Tests/\(nameAttribute)KitTests.swift",
              templatePath: templatePath("TestsKit.stencil")),
        .file(path: supportFrameworkPath + "/Sources/\(nameAttribute)Support.swift",
              templatePath: templatePath("SupportSourceContent.stencil")),
        .file(path: supportFrameworkPath + "/Tests/\(nameAttribute)SupportTests.swift",
              templatePath: templatePath("SupportTests.stencil")),
        .file(path: kitFrameworkPath + "/Playgrounds/\(nameAttribute)Kit.playground" + "/Contents.swift",
              templatePath: templatePath("PlaygroundContent.stencil")),
        .file(path: kitFrameworkPath + "/Playgrounds/\(nameAttribute)Kit.playground" + "/contents.xcplayground",
              templatePath: templatePath("Playground.stencil")),
        .file(path: supportFrameworkPath + "/Playgrounds/\(nameAttribute)Support.playground" + "/Contents.swift",
              templatePath: templatePath("PlaygroundContent.stencil")),
        .file(path: supportFrameworkPath + "/Playgrounds/\(nameAttribute)Support.playground" + "/contents.xcplayground",
              templatePath: templatePath("Playground.stencil")),
        .file(path: "Tuist/Config.swift",
              templatePath: templatePath("Config.stencil")),
        .file(path: ".gitignore",
              templatePath: templatePath("Gitignore.stencil")),
        .file(path: "Tuist/Templates/framework/Template.swift",
              templatePath: templatePath("ExampleTemplate.stencil")),
        .file(path: "Tuist/Templates/framework/project.stencil",
              templatePath: templatePath("ExampleProject")),
    ]
)
