import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        productTypes: ["StructBuilder": .framework]
    ),
    platforms: [.macOS, .iOS]
)
