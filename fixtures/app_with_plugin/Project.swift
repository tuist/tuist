import ExampleTuistPlugin
import LocalPlugin
import ProjectDescription
import ProjectDescriptionHelpers

// Test plugins are loaded
let localHelper = LocalHelper(name: "LocalPlugin")
let remoteHelper = RemoteHelper(name: "RemotePlugin")

let project = Project.app(
    name: "TuistPluginTest",
    platform: .iOS,
    additionalTargets: ["TuistPluginTestKit", "TuistPluginTestUI"]
)
