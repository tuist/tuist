import ProjectDescription

func appTarget(name: String) -> Target {
    .target(
        name: name,
        destinations: [.mac],
        product: .app,
        bundleId: "io.tuist.\(name)",
        infoPlist: .file(path: .relativeToManifest("Info.plist")),
        sources: .paths([.relativeToManifest("Sources/App/**")]),
        dependencies: [
            .target(name: "MyBundle"),
            .target(name: "MyFramework"),
        ],
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

func bundleTarget(name: String) -> Target {
    .target(
        name: name,
        destinations: [.mac],
        product: .bundle,
        bundleId: "io.tuist.\(name)",
        infoPlist: .default,
        sources: .paths([.relativeToManifest("Sources/MyBundle/**")]),
        dependencies: [
            .target(name: "MyFramework"),
        ],
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

func frameworkTarget(name: String) -> Target {
    .target(
        name: name,
        destinations: [.mac],
        product: .framework,
        bundleId: "io.tuist.\(name)",
        infoPlist: .file(path: .relativeToManifest("Info.plist")),
        sources: .paths([.relativeToManifest("Sources/MyFramework/**")]),
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

let project = Project(
    name: "App",
    targets: [
        appTarget(name: "App"),
        bundleTarget(name: "MyBundle"),
        frameworkTarget(name: "MyFramework")
    ]
)
