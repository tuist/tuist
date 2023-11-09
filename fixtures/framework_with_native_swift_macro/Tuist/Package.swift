// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FrameworkWithNativeSwiftMacro",
    dependencies: [
        .package(url: "https://github.com/alschmut/StructBuilderMacro.git", .exact("0.2.0")),
    ]
)
