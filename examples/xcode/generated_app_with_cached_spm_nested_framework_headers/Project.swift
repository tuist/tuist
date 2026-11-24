import ProjectDescription

// `Feature` imports `NestedKit`. `FeatureTests` only imports `Feature`, so once `Feature` is a cached binary, the
// tests compile against `NestedKit` only through `Feature`'s Swift module. Quoted includes in framework headers are
// errors, including in the Clang modules Swift precompiles, so QuotedKit's `#import "QKCompat.h"` must not fail once
// QuotedKit is a cached framework.
let project = Project(
    name: "App",
    settings: .settings(base: [
        "OTHER_CFLAGS": "$(inherited) -Werror=quoted-include-in-framework-header",
        "OTHER_SWIFT_FLAGS": "$(inherited) -Xcc -Werror=quoted-include-in-framework-header",
    ]),
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.App",
            sources: ["App/Sources/**"],
            dependencies: [.target(name: "Feature")]
        ),
        .target(
            name: "Feature",
            destinations: [.mac],
            product: .framework,
            bundleId: "dev.tuist.Feature",
            sources: ["Feature/Sources/**"],
            dependencies: [.external(name: "NestedKit"), .external(name: "QuotedKit")]
        ),
        .target(
            name: "FeatureTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "dev.tuist.FeatureTests",
            sources: ["FeatureTests/Sources/**"],
            dependencies: [.target(name: "Feature")]
        ),
    ]
)
