import ProjectDescription

let nameAttributeFour: Template.Attribute = .required("name")
let platformAttributeFour: Template.Attribute = .optional("platform", default: "ios")

let testContentsFour = """
// this is test \(nameAttributeFour) content
"""

let templateFour = Template(
    description: "Custom template",
    attributes: [
        nameAttributeFour,
        platformAttributeFour,
    ],
    items: [
        .string(path: "\(nameAttributeFour)/custom.swift", contents: testContentsFour),
        .file(path: "\(nameAttributeFour)/generated.swift", templatePath: "platform_four.stencil"),
        .directory(path: "\(nameAttributeFour)", sourcePath: "sourceFolder"),
    ]
)
