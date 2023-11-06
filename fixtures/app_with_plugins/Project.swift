import ProjectDescription
import ProjectDescriptionHelpers

import ExampleTuistPlugin
import LocalPlugin

// Test plugins are loaded
let localHelper = LocalHelper(name: "LocalPlugin")
let remoteHelper = RemoteHelper(name: "RemotePlugin")

let project = Project.app(
    name: "TuistPluginTest",
    platform: .iOS,
    additionalTargets: ["TuistPluginTestKit", "TuistPluginTestUI"]
)
