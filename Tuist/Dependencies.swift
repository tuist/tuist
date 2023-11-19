import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        productTypes: [
            "ArgumentParser": .framework,
        ]
    ),
    platforms: [.macOS]
)
