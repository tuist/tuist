import ProjectDescription

// Intentionally minimal and built only from long-stable ProjectDescription APIs
// so the oldest supported CLI version can still compile this manifest. Do not
// introduce newer APIs (e.g. buildableFolders) here — see
// e2e/module_cache_backward_compat.bats.
let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.modulecacheapp",
            infoPlist: .default,
            sources: "App/Sources/**",
            dependencies: [
                .target(name: "Framework"),
            ]
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.modulecacheapp.framework",
            sources: "Framework/Sources/**",
            dependencies: []
        ),
    ]
)
