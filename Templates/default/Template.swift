import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "iOS")

let setupContent = """
import ProjectDescription

let setup = Setup([
    // .homebrew(packages: ["swiftlint", "carthage"]),
    // .carthage()
])
"""
let projectsPath = "Projects"
let appPath = projectsPath + "/\(nameAttribute)"
let kitFrameworkPath = projectsPath + "/\(nameAttribute)Kit"
let supportFrameworkPath = projectsPath + "/\(nameAttribute)Support"

let workspaceContent = """
import ProjectDescription
import ProjectDescriptionHelpers

let workspace = Workspace(name: "\(nameAttribute)", projects: [
    "Projects/\(nameAttribute)",
    "Projects/\(nameAttribute)Kit",
    "Projects/\(nameAttribute)Support"
])
"""

func testsContent(_ name: String) -> String {
    """
    import Foundation
    import XCTest
    
    @testable import \(name)

    final class \(name)Tests: XCTestCase {
    
    }
    """
}

let kitSourceContent = """
import Foundation
import \(nameAttribute)Support

public final class \(nameAttribute)Kit {}
"""

let supportSourceContent = """
import Foundation

public final class \(nameAttribute)Support {}
"""

let playgroundContent = """
//: Playground - noun: a place where people can play

import Foundation

"""

let configContent = """
import ProjectDescription

let config = Config(generationOptions: [
])
"""

let template = Template(
    description: "Default template",
    files: [
        .string(path: "Setup.swift",
                contents: setupContent),
        .string(path: "Workspace.swift",
                contents: workspaceContent),
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
        .string(path: appPath + "/Tests/\(nameAttribute)Tests.swift",
                contents: testsContent("\(nameAttribute)")),
        .string(path: kitFrameworkPath + "/Sources/\(nameAttribute)Kit.swift",
                contents: kitSourceContent),
        .string(path: kitFrameworkPath + "/Tests/\(nameAttribute)KitTests.swift",
                contents: testsContent("\(nameAttribute)Kit")),
        .string(path: supportFrameworkPath + "/Sources/\(nameAttribute)Support.swift",
                contents: supportSourceContent),
        .string(path: supportFrameworkPath + "/Tests/\(nameAttribute)SupportTests.swift",
                contents: testsContent("\(nameAttribute)Support")),
        .string(path: kitFrameworkPath + "/Playgrounds/\(nameAttribute)Kit.playground" + "/Contents.swift",
                contents: playgroundContent),
        .file(path: kitFrameworkPath + "/Playgrounds/\(nameAttribute)Kit.playground" + "/contents.xcplayground",
              templatePath: "Playground.stencil"),
        .string(path: supportFrameworkPath + "/Playgrounds/\(nameAttribute)Support.playground" + "/Contents.swift",
                contents: playgroundContent),
        .file(path: supportFrameworkPath + "/Playgrounds/\(nameAttribute)Support.playground" + "/contents.xcplayground",
              templatePath: "Playground.stencil"),
        .string(path: "Tuist/Config.swift",
                contents: configContent),
        .file(path: ".gitignore",
              templatePath: "Gitignore.stencil"),
        .file(path: "Tuist/Templates/framework/Template.swift",
              templatePath: "ExampleTemplate.stencil"),
        .file(path: "Tuist/Templates/framework/project.stencil",
              templatePath: "ExampleProject"),
    ]
)
