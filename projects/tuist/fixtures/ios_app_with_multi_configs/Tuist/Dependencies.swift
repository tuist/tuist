import ProjectDescription

let settings: Settings = .settings(
    configurations: [
        .debug(name: "Debug", xcconfig: "ConfigurationFiles/Debug.xcconfig"),
        .release(name: "Beta", xcconfig: "ConfigurationFiles/Beta.xcconfig"),
        .release(name: "Release", xcconfig: "ConfigurationFiles/Release.xcconfig"),
    ]
)

let dependencies = Dependencies(
    swiftPackageManager: .init(
        [.local(path: "LocalSwiftPackage")],
        baseSettings: settings
    ),
    platforms: [.iOS]
)
