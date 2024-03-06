import ProjectDescription

func target(name: String) -> Target {
    .target(
        name: name,
        destinations: [.mac],
        product: .app,
        bundleId: "io.tuist.\(name)",
        infoPlist: .file(path: .relativeToManifest("Info.plist")),
        sources: .paths([.relativeToManifest("Sources/**")]),
        copyFiles: [
            .sharedSupport(
                name: "Copy Templates",
                subpath: "Templates",
                files: [.glob(pattern: "Templates/**", condition: .when([.macos]))]
            ),
        ],
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

let project = Project(
    name: "App",
    targets: [target(name: "App")]
)
