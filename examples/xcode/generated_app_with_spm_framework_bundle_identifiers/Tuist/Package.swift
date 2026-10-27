// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(baseProductType: .framework)
#endif

let package = Package(
    name: "App",
    dependencies: [.package(path: "../IssueReporting")]
)
