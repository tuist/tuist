import Foundation
import Testing
@testable import SwifterPMCore

struct NetrcTests {
    @Test
    func parserMatchesHostAndFallsBackToDefault() throws {
        let machines = NetrcParser.machines(
            in: """
            machine registry.example.com login example password secret
            default login fallback password fallback-secret
            """
        )
        let netrc = Netrc(sources: [NetrcSource(origin: .file, machines: machines)])

        #expect(
            netrc.credential(for: try #require(URL(string: "https://registry.example.com")))?
                .password == "secret")
        #expect(
            netrc.credential(for: try #require(URL(string: "https://other.example.com")))?
                .password == "fallback-secret")
    }

    @Test
    func credentialUsesTheFirstEntryForADuplicatedHost() throws {
        // SwiftPM's own netrc resolves duplicates with `machines.firstIndex(where:)`,
        // and curl sends the first entry too, so a file that both tools read one way
        // must not authenticate differently here.
        let machines = NetrcParser.machines(
            in: """
            machine registry.example.com login first password one
            machine registry.example.com login second password two
            """
        )
        let netrc = Netrc(sources: [NetrcSource(origin: .file, machines: machines)])

        #expect(
            netrc.credential(for: try #require(URL(string: "https://registry.example.com")))?
                .password == "one")
    }

    @Test
    func parserKeepsAHashInsideAValueAndStripsATrailingComment() {
        // curl and SwiftPM both open a comment only where `#` starts a token, so a
        // password containing one has to survive whole. Truncating it silently sends
        // a wrong password, which reads as bad credentials rather than bad parsing.
        let machines = NetrcParser.machines(
            in: "machine registry.example.com login user password se#cret # trailing"
        )

        #expect(
            machines == [
                NetrcMachine(name: "registry.example.com", login: "user", password: "se#cret")
            ])
    }

    @Test
    func parserSkipsEntriesWithoutBothCredentials() {
        let machines = NetrcParser.machines(
            in: """
            machine incomplete.example.com login example
            machine complete.example.com login example password secret
            """
        )

        #expect(machines == [NetrcMachine(name: "complete.example.com", login: "example", password: "secret")])
    }

    @Test
    func resolveReadsTheConfiguredNetrcFile() async throws {
        try await withTemporaryDirectory { root in
            let netrcFile = root.appendingPathComponent("netrc")
            try await fileSystem.atomicWrite(
                "machine registry.example.com login example password from-file",
                to: netrcFile
            )

            let netrc = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(path: netrcFile), environment: [:])
            let credential = netrc.credential(
                for: try #require(URL(string: "https://registry.example.com")))

            #expect(credential?.user == "example")
            #expect(credential?.password == "from-file")
        }
    }

    @Test
    func configuredNetrcFileReplacesHomeButNotEnvironmentData() async throws {
        // SwiftPM reads SWIFTPM_NETRC_DATA before it switches on which file to use, so
        // an explicit `--netrc-file` displaces `~/.netrc` and nothing else.
        try await withTemporaryDirectory { root in
            let netrcFile = root.appendingPathComponent("netrc")
            try await fileSystem.atomicWrite(
                """
                machine registry.example.com login example password from-file
                machine other.example.com login example password file-only
                """,
                to: netrcFile
            )
            try await fileSystem.atomicWrite(
                "machine home.example.com login example password from-home",
                to: root.appendingPathComponent(".netrc")
            )

            let netrc = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(path: netrcFile),
                environment: [
                    "HOME": root.path,
                    "SWIFTPM_NETRC_DATA":
                        "machine registry.example.com login example password from-environment",
                ]
            )

            #expect(
                netrc.credential(for: try #require(URL(string: "https://registry.example.com")))?
                    .password == "from-environment")
            #expect(
                netrc.credential(for: try #require(URL(string: "https://other.example.com")))?
                    .password == "file-only")
            #expect(
                netrc.credential(for: try #require(URL(string: "https://home.example.com"))) == nil)
        }
    }

    @Test
    func environmentDataWinsButHomeStillCoversOtherHosts() async throws {
        try await withTemporaryDirectory { root in
            try await fileSystem.atomicWrite(
                """
                machine registry.example.com login example password from-home
                machine other.example.com login example password home-only
                """,
                to: root.appendingPathComponent(".netrc")
            )

            let netrc = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(),
                environment: [
                    "HOME": root.path,
                    "SWIFTPM_NETRC_DATA":
                        "machine registry.example.com login example password from-environment",
                ]
            )

            #expect(
                netrc.credential(for: try #require(URL(string: "https://registry.example.com")))?
                    .password == "from-environment")
            #expect(
                netrc.credential(for: try #require(URL(string: "https://other.example.com")))?
                    .password == "home-only")
        }
    }

    @Test
    func credentialFromAnOriginIgnoresTheOtherSources() async throws {
        // The registry path asks for each origin separately so it can consult the
        // keychain between them, the way SwiftPM's registry provider does.
        try await withTemporaryDirectory { root in
            try await fileSystem.atomicWrite(
                "machine registry.example.com login example password from-home",
                to: root.appendingPathComponent(".netrc")
            )

            let netrc = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(),
                environment: [
                    "HOME": root.path,
                    "SWIFTPM_NETRC_DATA":
                        "machine other.example.com login example password from-environment",
                ]
            )
            let registry = try #require(URL(string: "https://registry.example.com"))
            let other = try #require(URL(string: "https://other.example.com"))

            #expect(netrc.credential(for: registry, from: .environment) == nil)
            #expect(netrc.credential(for: registry, from: .file)?.password == "from-home")
            #expect(netrc.credential(for: other, from: .environment)?.password == "from-environment")
            #expect(netrc.credential(for: other, from: .file) == nil)
        }
    }

    @Test
    func resolveFallsBackToTheHomeNetrcFile() async throws {
        try await withTemporaryDirectory { root in
            try await fileSystem.atomicWrite(
                "machine registry.example.com login example password from-home",
                to: root.appendingPathComponent(".netrc")
            )

            let netrc = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(), environment: ["HOME": root.path])

            #expect(
                netrc.credential(for: try #require(URL(string: "https://registry.example.com")))?
                    .password == "from-home")
        }
    }

    @Test
    func disabledNetrcIgnoresEveryCredentialSource() async throws {
        try await withTemporaryDirectory { root in
            try await fileSystem.atomicWrite(
                "machine registry.example.com login example password from-home",
                to: root.appendingPathComponent(".netrc")
            )

            let netrc = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(isEnabled: false),
                environment: [
                    "HOME": root.path,
                    "SWIFTPM_NETRC_DATA":
                        "machine registry.example.com login example password from-environment",
                ]
            )

            #expect(
                netrc.credential(for: try #require(URL(string: "https://registry.example.com")))
                    == nil)
        }
    }

    @Test
    func resolveRejectsAMissingConfiguredNetrcFile() async throws {
        try await withTemporaryDirectory { root in
            let missing = root.appendingPathComponent("netrc")

            await #expect(throws: (any Error).self) {
                try await Netrc.resolve(
                    SwifterPMNetrcConfiguration(path: missing), environment: [:])
            }
        }
    }

    @Test
    func resolveIgnoresAMissingNetrcFileWhenDisabledOrUnconfigured() async throws {
        try await withTemporaryDirectory { root in
            let missing = root.appendingPathComponent("netrc")

            _ = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(isEnabled: false, path: missing), environment: [:])
            _ = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(), environment: ["HOME": root.path])
        }
    }

    @Test
    func registryAuthorizationUsesTheLoadedNetrc() async throws {
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
            let netrc = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(path: netrcFile), environment: [:])

            let header = try await Environment.$values.withValue([:]) {
                try await Environment.withNetrc(netrc) {
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
    func httpAuthorizationUsesTheLoadedNetrcOverTheAmbientGitHubToken() async throws {
        try await withTemporaryDirectory { root in
            let netrcFile = root.appendingPathComponent("netrc")
            try await fileSystem.atomicWrite(
                "machine api.github.com login x-access-token password from-file",
                to: netrcFile
            )
            let netrc = try await Netrc.resolve(
                SwifterPMNetrcConfiguration(path: netrcFile), environment: [:])

            let header = try await Environment.$values.withValue(["GITHUB_TOKEN": "ambient"]) {
                try await Environment.withNetrc(netrc) {
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
