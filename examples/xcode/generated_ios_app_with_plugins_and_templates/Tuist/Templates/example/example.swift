import ProjectDescription
import ProjectDescriptionHelpers

let template = Template(
    description: "example",
    items: [.item(
        path: "./Sources/LocalTemplateTest.swift",

        contents: .string("// Generated file named \(Constants.name) from local template")
    )]
)
