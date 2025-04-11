import ProjectDescription

let project = Project(
    name: "GeneratediOSStaticLibraryWithStringResources",
    targets: [
        .target(
            name: "GeneratediOSStaticLibraryWithStringResources",
            destinations: .iOS,
            product: .staticLibrary,
            bundleId: "io.tuist.GeneratediOSStaticLibraryWithStringResources",
            sources: ["GeneratediOSStaticLibraryWithStringResources/Sources/**"],
            resources: ["GeneratediOSStaticLibraryWithStringResources/Resources/**"],
            dependencies: []
        ),
    ]
)
