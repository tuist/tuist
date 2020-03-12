import ProjectDescription

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
        .string(path: "custom_dir/custom.swift", contents: testContents)
    ],
    directories: ["custom_dir"]
)
