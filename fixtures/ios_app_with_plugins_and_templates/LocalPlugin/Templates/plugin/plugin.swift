import LocalPlugin
import ProjectDescription

let template = Template(
    description: "plugin",
    items: [.item(
        path: "./Sources/PluginTemplateTest.swift",

        contents: .string("// Generated file named \(Project.name) from plugin")
    )]
)
