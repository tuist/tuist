import ProjectDescription
import TemplateDescription

let nameArgument: Template.Attribute = .required("name")
let platformArgument: Template.Attribute = .optional("platform", default: "ios")

let testContents = """
// this is test \(nameArgument) content

"""

let template = Template(
    description: "Custom \(nameArgument)",
    arguments: [
        nameArgument,
        platformArgument
    ],
    files: [
        .static(path: "custom_dir/custom.swift",
                contents: testContents),
        .generated(path: "custom_dir/custom_generated.swift",
                   generateFilePath: "generate.swift"),
    ],
    directories: ["custom_dir"]
)
