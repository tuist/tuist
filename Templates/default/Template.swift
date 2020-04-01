import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")

let projectsPath = "Projects"
let appPath = projectsPath + "/\(nameAttribute)"
let kitFrameworkPath = projectsPath + "/\(nameAttribute)Kit"
let supportFrameworkPath = projectsPath + "/\(nameAttribute)Support"

let template = Template(
    description: "Default template",
    files: [
        .file(path: "Setup.swift",
              templatePath: "Setup.stencil"),
        .file(path: "Workspace.swift",
              templatePath: "Workspace.stencil"),
        .file(path: "Tuist/ProjectDescriptionHelpers/Project+Templates.swift",
              templatePath: "Project+Templates.stencil"),
        .file(path: appPath + "/Project.swift",
              templatePath: "AppProject.stencil"),
        .file(path: kitFrameworkPath + "/Project.swift",
              templatePath: "KitFrameworkProject.stencil"),
        .file(path: supportFrameworkPath + "/Project.swift",
              templatePath: "SupportFrameworkProject.stencil"),
        .file(path: appPath + "/Sources/AppDelegate.swift",
              templatePath: "AppDelegate.stencil"),
        .file(path: appPath + "/Tests/\(nameAttribute)Tests.swift",
              templatePath: "Tests.stencil"),
        .file(path: kitFrameworkPath + "/Sources/\(nameAttribute)Kit.swift",
              templatePath: "KitSource.stencil"),
        .file(path: kitFrameworkPath + "/Tests/\(nameAttribute)KitTests.swift",
              templatePath: "TestsKit.stencil"),
        .file(path: supportFrameworkPath + "/Sources/\(nameAttribute)Support.swift",
              templatePath: "SupportSourceContent.stencil"),
        .file(path: supportFrameworkPath + "/Tests/\(nameAttribute)SupportTests.swift",
              templatePath: "SupportTests.stencil"),
        .file(path: kitFrameworkPath + "/Playgrounds/\(nameAttribute)Kit.playground" + "/Contents.swift",
              templatePath: "PlaygroundContent.stencil"),
        .file(path: kitFrameworkPath + "/Playgrounds/\(nameAttribute)Kit.playground" + "/contents.xcplayground",
              templatePath: "Playground.stencil"),
        .file(path: supportFrameworkPath + "/Playgrounds/\(nameAttribute)Support.playground" + "/Contents.swift",
              templatePath: "PlaygroundContent.stencil"),
        .file(path: supportFrameworkPath + "/Playgrounds/\(nameAttribute)Support.playground" + "/contents.xcplayground",
              templatePath: "Playground.stencil"),
        .file(path: "Tuist/Config.swift",
              templatePath: "Config.stencil"),
        .file(path: ".gitignore",
              templatePath: "Gitignore.stencil"),
        .file(path: "Tuist/Templates/framework/Template.swift",
              templatePath: "ExampleTemplate.stencil"),
        .file(path: "Tuist/Templates/framework/project.stencil",
              templatePath: "ExampleProject"),
    ]
)
