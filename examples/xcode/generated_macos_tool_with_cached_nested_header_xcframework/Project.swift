import ProjectDescription

// Reproduces the ARCore caching failure: a static Objective-C `.a` xcframework
// (`NestedObjC`) whose headers live in a `Headers/NestedObjC/` subdirectory and
// re-import each other with the `<NestedObjC/...>` prefix, linked by a dynamic
// framework (`Library`). When `Library` is cached, `Library.xcframework` becomes
// a dynamic dependency that links `NestedObjC` behind it, so `Tool` consumes
// `NestedObjC` as a static-objc-xcframework-behind-a-dynamic-xcframework — the
// path handled by `StaticXCFrameworkModuleMapGraphMapper`.
let project = Project(
    name: "NestedHeaderXCFramework",
    organizationName: "tuist.io",
    settings: .settings(base: [
        "SWIFT_ENABLE_EXPLICIT_MODULES": false,
    ]),
    targets: [
        .target(
            name: "Tool",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "io.tuist.NestedHeaderXCFramework.Tool",
            infoPlist: .default,
            sources: ["Tool/Sources/**"],
            dependencies: [
                .target(name: "Library"),
            ]
        ),
        .target(
            name: "Library",
            destinations: .macOS,
            product: .framework,
            bundleId: "io.tuist.NestedHeaderXCFramework.Library",
            infoPlist: .default,
            sources: ["Library/Sources/**"],
            dependencies: [
                .xcframework(path: "NestedObjC.xcframework"),
                .xcframework(path: "NestedObjCKit.xcframework"),
            ]
        ),
    ]
)
