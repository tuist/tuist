
import ProjectDescription

let nameAttributeThree: Template.Attribute = .required("name")
let platformAttributeThree: Template.Attribute = .optional("platform", default: "IOS")

let testContentsThree = """
// this is test \(nameAttributeThree) content
"""

let templateThree = Template(
    description: "Custom template",
    attributes: [
        nameAttributeThree,
        platformAttributeThree,
    ],
    items: [
        .string(path: "\(nameAttributeThree)/custom.swift", contents: testContentsThree),
        .file(path: "\(nameAttributeThree)/generated.swift", templatePath: "filters.stencil"),
    ]
)
