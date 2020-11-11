import ProjectDescription
import ProjectDescriptionHelpers
import LocalTuistHelpers

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "ios")

let testContents = """
// this is test \(nameAttribute) content
"""

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        platformAttribute
    ],
    files: [
        .string(path: "\(nameAttribute)/custom.swift", contents: testContents),
        .file(path: "\(nameAttribute)/generated.swift", templatePath: "platform.stencil"),
    ]
)
