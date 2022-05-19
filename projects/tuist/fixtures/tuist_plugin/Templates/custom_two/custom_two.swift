import ProjectDescription

let nameAttributeTwo: Template.Attribute = .required("name")
let platformAttributeTwo: Template.Attribute = .optional("platform", default: "ios")

let testContentsTwo = """
// this is test \(nameAttributeTwo) content
"""

let templateTwo = Template(
    description: "Custom template",
    attributes: [
        nameAttributeTwo,
        platformAttributeTwo
    ],
    items: [
        .string(path: "\(nameAttributeTwo)/custom.swift", contents: testContentsTwo),
        .file(path: "\(nameAttributeTwo)/generated.swift", templatePath: "platform_two.stencil"),
    ]
)
