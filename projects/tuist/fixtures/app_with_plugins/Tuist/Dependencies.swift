import ExampleTuistPlugin
import LocalPlugin
import ProjectDescription

// Note: Testing importing of plugins in local helpers
let localPlugin = LocalHelper(name: "local")
let remotePlugin = RemoteHelper(name: "remote")

let dependencies = Dependencies(
    swiftPackageManager: .init(
        [],
        targetSettings: [:]
    ),
    platforms: [.iOS, .macOS]
)
