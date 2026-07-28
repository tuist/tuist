import ProjectDescription

// Reproduces a binary-cache failure: a static Objective-C `.a` xcframework
// (`NestedObjC`) whose headers live in a `Headers/NestedObjC/` subdirectory and
// re-import each other with the `<NestedObjC/...>` prefix, linked by a dynamic
// framework (`Library`). When `Library` is cached, `Library.xcframework` becomes
// a dynamic dependency that links `NestedObjC` behind it, so `Tool` consumes
// `NestedObjC` as a static-objc-xcframework-behind-a-dynamic-xcframework, the
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
        // Same as `Tool`, but the xcframeworks are *also* linked directly. Once
        // `Library` is replaced by its cached xcframework, `Tool` no longer
        // references `NestedObjC.xcframework` at all, so Xcode never processes it.
        // Here the direct link keeps it referenced, so Xcode runs
        // `ProcessXCFramework` and copies each slice's headers into
        // `$(BUILT_PRODUCTS_DIR)/include/<Module>/`. That directory is searched
        // before `HEADER_SEARCH_PATHS`, so `#import <NestedObjC/Anchor.h>` resolves
        // to Xcode's copy rather than to the headers the module map was pointed at.
        // A real project reaches the same state whenever anything else in the graph
        // still references the xcframework.
        .target(
            name: "ToolLinkingXCFrameworksDirectly",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "io.tuist.NestedHeaderXCFramework.ToolLinkingXCFrameworksDirectly",
            infoPlist: .default,
            sources: ["Tool/Sources/**"],
            dependencies: [
                .target(name: "Library"),
                .xcframework(path: "NestedObjC.xcframework"),
                .xcframework(path: "NestedObjCKit.xcframework"),
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
