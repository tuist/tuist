import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(manifest: "Package.swift"),
    platforms: [.macOS]
)
