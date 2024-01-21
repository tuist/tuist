// swift-tools-version: 5.8
import PackageDescription

#if TUIST

    import ExampleTuistPlugin
    import LocalPlugin
    import ProjectDescription

    // Note: Testing importing of plugins in local helpers
    let localPlugin = LocalHelper(name: "local")
    let remotePlugin = RemoteHelper(name: "remote")

    let packageSettings = PackageSettings(
        platforms: [.iOS, .macOS]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: []
)
