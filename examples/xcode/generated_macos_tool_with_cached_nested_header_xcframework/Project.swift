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
        // A `.staticFramework` that links the same static nested-header xcframeworks. When it's
        // cached and a consumer links it, `LinkGenerator`'s transitive-static relink pulls the
        // wrapped xcframeworks into the consumer's Frameworks build phase — Xcode then runs
        // `ProcessXCFramework` on them and copies `Headers/<Module>/` into
        // `$(BUILT_PRODUCTS_DIR)/include/<Module>/`. The direct-graph-edge suppression walker
        // never saw this shape, so a sibling target reaching the same xcframework via the
        // cached dynamic `Library` still got vendor `Headers/` on `HEADER_SEARCH_PATHS`
        // added by `StaticXCFrameworkModuleMapGraphMapper`, and Clang's dep scanner rejected
        // both maps with `redefinition of module`.
        .target(
            name: "StaticWrapper",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "io.tuist.NestedHeaderXCFramework.StaticWrapper",
            infoPlist: .default,
            sources: ["StaticWrapper/Sources/**"],
            dependencies: [
                .xcframework(path: "NestedObjC.xcframework"),
                .xcframework(path: "NestedObjCKit.xcframework"),
            ]
        ),
        // Consumes both the cached `StaticWrapper` (which transitively relinks the nested
        // xcframeworks at this level) and the cached dynamic `Library` (which routes the
        // same xcframeworks through the mapper's dynamic-behind walker). Without the
        // linkable-dependencies suppression widening, this target sees both the
        // `include/<Module>/module.modulemap` copy from `ProcessXCFramework` and the
        // vendor `Headers/<Module>/module.modulemap` on the search path, and Clang's
        // dep scanner fails with `redefinition of module`.
        .target(
            name: "ToolLinkingStaticAndDynamicWrappers",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "io.tuist.NestedHeaderXCFramework.ToolLinkingStaticAndDynamicWrappers",
            infoPlist: .default,
            sources: ["ToolLinkingStaticAndDynamicWrappers/Sources/**"],
            dependencies: [
                .target(name: "Library"),
                .target(name: "StaticWrapper"),
            ],
            // `redefinition of module` fires from Clang's explicit-modules dependency scanner.
            // The project-level default disables explicit modules to keep the earlier fixtures
            // focused on the umbrella-header / shadowed-module class of failures; override it
            // here so this test actually exercises the dep-scan path where the redefinition
            // surfaces.
            settings: .settings(base: [
                "SWIFT_ENABLE_EXPLICIT_MODULES": "YES",
            ])
        ),
    ]
)
