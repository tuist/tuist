import TapestryDescription

let config = TapestryConfig(
    release: Release(
        actions:
        [
            .pre(tool: "git", arguments: ["checkout", "master"]),
            .pre(tool: "git", arguments: ["pull"]),
            .pre(.dependenciesCompatibility([.spm(.all)])),
            .pre(tool: "swift", arguments: ["test"]),
            .pre(tool: "bundle", arguments: ["exec", "rake", "features"]),
            .pre(.docsUpdate),
            .pre(tool: "sudo", arguments: ["xcode-select", "-s", "/Applications/Xcode_11.5.app"]),
            .post(tool: "bundle", arguments: ["exec", "rake", "release"]),
            .post(tool: "bundle", arguments: ["exec", "rake", "release_scripts"]),
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
