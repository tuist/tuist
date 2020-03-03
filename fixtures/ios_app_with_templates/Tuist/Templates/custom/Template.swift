import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let platformAttribute: Template.Attribute = .optional("platform", default: "ios")

let testContents = """
// this is test \(nameAttribute) content

"""

let template = Template(
    description: "Custom \(nameAttribute)",
    attributes: [
        nameAttribute,
        platformAttribute
    ],
    files: [
        .static(path: "custom_dir/custom.swift",
                contents: testContents),
        .generated(path: "custom_dir/custom_generated.swift",
                   generateFilePath: "generate.swift"),
    ],
    directories: ["custom_dir"]
)
