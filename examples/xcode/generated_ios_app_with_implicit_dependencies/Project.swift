import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .target(name: "FrameworkA"),
                .target(name: "FrameworkB"),
            ]
        ),
        .target(
            name: "FrameworkA",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.FrameworkA",
            sources: ["Targets/FrameworkA/Sources/**"]
        ),
        .target(
            name: "FrameworkB",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.FrameworkB",
            sources: ["Targets/FrameworkB/Sources/**"]
        ),
        .target(
            name: "FrameworkC",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.FrameworkC",
            sources: ["Targets/FrameworkC/Sources/**"],
            dependencies: [],
            metadata: .metadata(tags: ["IgnoreRedundantDependencies"])
        ),
        .target(
            name: "ProtocolModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.ProtocolModule",
            sources: ["Targets/ProtocolModule/Sources/**"]
        ),
        .target(
            name: "StructModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.StructModule",
            sources: ["Targets/StructModule/Sources/**"]
        ),
        .target(
            name: "EnumModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.EnumModule",
            sources: ["Targets/EnumModule/Sources/**"]
        ),
        .target(
            name: "ClassModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.ClassModule",
            sources: ["Targets/ClassModule/Sources/**"]
        ),
        .target(
            name: "FuncModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.FuncModule",
            sources: ["Targets/FuncModule/Sources/**"]
        ),
        .target(
            name: "VarModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.VarModule",
            sources: ["Targets/VarModule/Sources/**"]
        ),
        .target(
            name: "LetModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.LetModule",
            sources: ["Targets/LetModule/Sources/**"]
        ),
        .target(
            name: "TypeAliasModule",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.TypeAliasModule",
            sources: ["Targets/TypeAliasModule/Sources/**"]
        ),
    ]
)
