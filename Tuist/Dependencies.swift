import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(
        productTypes: [
            "SystemPackage": .staticFramework,
            "TSCBasic": .staticFramework,
            "TSCUtility": .staticFramework,
            "TSCclibc": .staticFramework,
            "TSCLibc": .staticFramework,
            "ArgumentParser": .staticFramework,
        ]
    ),
    platforms: [.macOS]
)
