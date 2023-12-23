import ProjectDescription

let project = Project(
    name: "SharedDependenciesFramework",
    targets: [
        Target(
            name: "SharedDependenciesFramework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.SharedDependenciesFramework",
            infoPlist: .default,
            sources: [], // no sources, it only wraps dependencies to share between executables
            dependencies: [
                .project(target: "DynamicFrameworkA", path: "../DynamicFrameworkA"),
                .project(target: "DynamicFrameworkB", path: "../DynamicFrameworkB"),
                .xcframework(path: "../XCFrameworks/MergeableXCFramework/prebuilt/MergeableXCFramework.xcframework"),
            ],
            mergedBinaryType: .automatic
        ),
    ]
)
