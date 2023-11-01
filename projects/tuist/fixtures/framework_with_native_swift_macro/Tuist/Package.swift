// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FrameworkWithNativeSwiftMacro",
    dependencies: [
        .remote(url: "https://github.com/alschmut/StructBuilderMacro.git", requirement: .exact("0.2.0"))
    ]
)
