import ProjectDescription

let project = Project(
    name: "GeneratediOSStaticLibraryWithStringResources",
    settings: .settings(
        base: ["VERSIONING_SYSTEM": "apple-generic"],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "GeneratediOSStaticLibraryWithStringResources",
            destinations: .iOS,
            product: .staticLibrary,
            bundleId: "dev.tuist.GeneratediOSStaticLibraryWithStringResources",
            sources: ["GeneratediOSStaticLibraryWithStringResources/Sources/**"],
            resources: ["GeneratediOSStaticLibraryWithStringResources/Resources/**"],
            dependencies: []
        ),
    ]
)
