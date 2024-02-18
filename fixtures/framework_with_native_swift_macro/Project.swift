import ProjectDescription

let project = Project(
    name: "FrameworkWithSwiftMacro",
    targets: [
        Target(
            name: "Framework",
            destinations: [.iPhone, .mac],
            //destinations: .iOS,
            product: .staticLibrary,
            bundleId: "io.tuist.FrameworkWithSwiftMacro",
            deploymentTargets: .iOS("15.0"),
            sources: ["Sources/**/*"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
                .external(name: "CasePaths"),
                .external(name: "StructBuilder"),
            ]
        ),
    ]
)
