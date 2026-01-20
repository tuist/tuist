import ProjectDescription

func bundleTarget(name: String) -> Target {
    .target(
        name: name,
        destinations: [.mac],
        product: .bundle,
        bundleId: "dev.tuist.\(name)",
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
        bundleId: "dev.tuist.\(name)",
        infoPlist: .file(path: .relativeToManifest("Info.plist")),
        sources: .paths([.relativeToManifest("Sources/MyFramework/**")]),
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

let project = Project(
    name: "Bundle",
    targets: [
        bundleTarget(name: "MyBundle"),
        frameworkTarget(name: "MyFramework"),
    ]
)
