import Foundation
import Testing
@testable import SwifterPMCore

struct NetrcTests {
    @Test
    func credentialReadsTheConfiguredNetrcFile() async throws {
        try await withTemporaryDirectory { root in
            let netrcFile = root.appendingPathComponent("netrc")
            try await fileSystem.atomicWrite(
                "machine registry.example.com login example password from-file",
                to: netrcFile
            )

            let credential = try await Environment.withNetrc(
                SwifterPMNetrcConfiguration(path: netrcFile)
            ) {
                await Netrc.credential(
                    for: try #require(URL(string: "https://registry.example.com")),
                    environment: [:]
                )
            }

            #expect(credential?.user == "example")
            #expect(credential?.password == "from-file")
        }
    }

    @Test
    func configuredNetrcFileBeatsEnvironmentData() async throws {
        try await withTemporaryDirectory { root in
            let netrcFile = root.appendingPathComponent("netrc")
            try await fileSystem.atomicWrite(
                "machine registry.example.com login example password from-file",
                to: netrcFile
            )

            let credential = try await Environment.withNetrc(
                SwifterPMNetrcConfiguration(path: netrcFile)
            ) {
                await Netrc.credential(
                    for: try #require(URL(string: "https://registry.example.com")),
                    environment: [
                        "SWIFTPM_NETRC_DATA":
                            "machine registry.example.com login example password from-environment",
                    ]
                )
            }

            #expect(credential?.password == "from-file")
        }
    }

    @Test
    func credentialFallsBackToTheHomeNetrcFile() async throws {
        try await withTemporaryDirectory { root in
            try await fileSystem.atomicWrite(
                "machine registry.example.com login example password from-home",
                to: root.appendingPathComponent(".netrc")
            )

            let credential = await Netrc.credential(
                for: try #require(URL(string: "https://registry.example.com")),
                environment: ["HOME": root.path]
            )

            #expect(credential?.password == "from-home")
        }
    }

    @Test
    func disabledNetrcIgnoresEveryCredentialSource() async throws {
        try await withTemporaryDirectory { root in
            try await fileSystem.atomicWrite(
                "machine registry.example.com login example password from-home",
                to: root.appendingPathComponent(".netrc")
            )

            let credential = try await Environment.withNetrc(
                SwifterPMNetrcConfiguration(isEnabled: false)
            ) {
                await Netrc.credential(
                    for: try #require(URL(string: "https://registry.example.com")),
                    environment: [
                        "HOME": root.path,
                        "SWIFTPM_NETRC_DATA":
                            "machine registry.example.com login example password from-environment",
                    ]
                )
            }

            #expect(credential == nil)
        }
    }

    @Test
    func validateRejectsAMissingConfiguredNetrcFile() async throws {
        try await withTemporaryDirectory { root in
            let missing = root.appendingPathComponent("netrc")

            await #expect(throws: (any Error).self) {
                try await Netrc.validate(SwifterPMNetrcConfiguration(path: missing))
            }
        }
    }

    @Test
    func validateAcceptsAnExistingFileAMissingOneWhenDisabledAndNoFileAtAll() async throws {
        try await withTemporaryDirectory { root in
            let netrcFile = root.appendingPathComponent("netrc")
            try await fileSystem.atomicWrite("machine example.com login a password b", to: netrcFile)

            try await Netrc.validate(SwifterPMNetrcConfiguration(path: netrcFile))
            try await Netrc.validate(
                SwifterPMNetrcConfiguration(
                    isEnabled: false, path: root.appendingPathComponent("missing")))
            try await Netrc.validate(SwifterPMNetrcConfiguration())
        }
    }

    @Test
    func registryAuthorizationUsesTheConfiguredNetrcFile() async throws {
        try await withTemporaryDirectory { root in
            let netrcFile = root.appendingPathComponent("netrc")
            try await fileSystem.atomicWrite(
                "machine registry.example.com login user password secret",
                to: netrcFile
            )
            let config = try await RegistryConfig.load(
                packageDir: root,
                configPath: nil,
                defaultRegistryURL: "https://registry.example.com"
            )

            let header = try await Environment.$values.withValue([:]) {
                try await Environment.withNetrc(SwifterPMNetrcConfiguration(path: netrcFile)) {
                    await RegistryAuthorization.header(
                        for: try #require(URL(string: "https://registry.example.com")),
                        registryConfig: config
                    )
                }
            }

            #expect(header == "Basic dXNlcjpzZWNyZXQ=")
        }
    }

    @Test
    func httpAuthorizationUsesTheConfiguredNetrcFileOverTheAmbientGitHubToken() async throws {
        try await withTemporaryDirectory { root in
            let netrcFile = root.appendingPathComponent("netrc")
            try await fileSystem.atomicWrite(
                "machine api.github.com login x-access-token password from-file",
                to: netrcFile
            )

            let header = try await Environment.$values.withValue(["GITHUB_TOKEN": "ambient"]) {
                try await Environment.withNetrc(SwifterPMNetrcConfiguration(path: netrcFile)) {
                    await HTTPAuthorization.header(
                        for: try #require(
                            URL(string: "https://api.github.com/repos/tuist/tuist/releases/assets/1"))
                    )
                }
            }

            #expect(header == "Basic eC1hY2Nlc3MtdG9rZW46ZnJvbS1maWxl")
        }
    }
}
