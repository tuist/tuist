import ProjectDescription

let project = Project(
    name: "CachedLibrariesAndFrameworks",
    organizationName: "tuist.dev",
    settings: .settings(base: [
        "SWIFT_ENABLE_EXPLICIT_MODULES": false,
    ]),
    targets: [
        .target(
            name: "Tool",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "io.tuist.CachedLibrariesAndFrameworks.Tool",
            infoPlist: .default,
            sources: ["Tool/Sources/**"],
            dependencies: [
                .target(name: "FeatureFramework"),
                .target(name: "DiagnosticsDynamicLibrary"),
                .target(name: "CoreCLibrary"),
            ]
        ),
        .target(
            name: "FeatureFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "io.tuist.CachedLibrariesAndFrameworks.FeatureFramework",
            infoPlist: .default,
            sources: ["FeatureFramework/Sources/**"],
            dependencies: [
                .target(name: "FeatureStaticLibrary"),
                .target(name: "NetworkingFramework"),
            ]
        ),
        .target(
            name: "NetworkingFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "io.tuist.CachedLibrariesAndFrameworks.NetworkingFramework",
            infoPlist: .default,
            sources: ["NetworkingFramework/Sources/**"],
            dependencies: [
                .target(name: "ModelsStaticFramework"),
            ]
        ),
        .target(
            name: "ModelsStaticFramework",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "io.tuist.CachedLibrariesAndFrameworks.ModelsStaticFramework",
            infoPlist: .default,
            sources: ["ModelsStaticFramework/Sources/**"],
            dependencies: [
                .target(name: "CoreStaticLibrary"),
            ]
        ),
        .target(
            name: "FeatureStaticLibrary",
            destinations: .macOS,
            product: .staticLibrary,
            bundleId: "io.tuist.CachedLibrariesAndFrameworks.FeatureStaticLibrary",
            infoPlist: nil,
            sources: ["FeatureStaticLibrary/Sources/**"],
            dependencies: [
                .target(name: "CoreStaticLibrary"),
            ]
        ),
        .target(
            name: "DiagnosticsDynamicLibrary",
            destinations: .macOS,
            product: .dynamicLibrary,
            bundleId: "io.tuist.CachedLibrariesAndFrameworks.DiagnosticsDynamicLibrary",
            infoPlist: .default,
            sources: ["DiagnosticsDynamicLibrary/Sources/**"]
        ),
        .target(
            name: "CoreStaticLibrary",
            destinations: .macOS,
            product: .staticLibrary,
            bundleId: "io.tuist.CachedLibrariesAndFrameworks.CoreStaticLibrary",
            infoPlist: nil,
            sources: ["CoreStaticLibrary/Sources/**"]
        ),
        .target(
            name: "CoreCLibrary",
            destinations: .macOS,
            product: .staticLibrary,
            bundleId: "io.tuist.CachedLibrariesAndFrameworks.CoreCLibrary",
            infoPlist: nil,
            sources: ["CoreCLibrary/Sources/**"],
            headers: .headers(public: "CoreCLibrary/Sources/**/*.h")
        ),
    ]
)
