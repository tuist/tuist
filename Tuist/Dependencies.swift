import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: .init(manifest: "Tuist/Package.swift"),
    platforms: [.macOS]
)
