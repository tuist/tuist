import ProjectDescription
import ProjectDescriptionHelpers

@preconcurrency import ExampleTuistPlugin
import LocalPlugin

// Test plugins are loaded

let localHelper = LocalHelper(name: "LocalPlugin")
let remoteHelper = RemoteHelper(name: "RemotePlugin")

let project = Project.app(
    name: "TuistPluginTest",
    destinations: .iOS,
    additionalTargets: ["TuistPluginTestKit", "TuistPluginTestUI"]
)
