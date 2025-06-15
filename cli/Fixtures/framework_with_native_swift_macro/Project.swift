import ProjectDescription

let project = Project(
    name: "FrameworkWithSwiftMacro",
    targets: [
        .target(
            name: "Framework",
            destinations: [.iPhone, .mac],
            product: .staticLibrary,
            bundleId: "io.tuist.FrameworkWithSwiftMacro",
            sources: ["Sources/**/*"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
                .external(name: "CasePaths"),
                .external(name: "StructBuilder"),
            ]
        ),
    ]
)
