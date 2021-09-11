import TapestryDescription

let config = TapestryConfig(
    release: Release(
        actions:
        [
            .pre(tool: "git", arguments: ["checkout", "main"]),
            .pre(tool: "git", arguments: ["pull"]),
            .pre(tool: "bundle", arguments: ["install"]),
            .pre(tool: "sudo", arguments: ["xcode-select", "-s", "/Applications/Xcode_12.4.app"]),
            .pre(.dependenciesCompatibility([.spm(.all)])),
            .pre(tool: "swift", arguments: ["test"]),
            .pre(.docsUpdate),
            .post(tool: "./fourier", arguments: ["release", "tuist", "\(Argument.version)"]),
            .post(
                .githubRelease(
                    owner: "tuist",
                    repository: "tuist",
                    assetPaths: [
                        "build/tuist.zip",
                        "build/tuistenv.zip",
                    ]
                )
            ),
        ],
        add: [
            "CHANGELOG.md",
        ],
        commitMessage: "Version \(Argument.version)",
        push: true
    )
)
