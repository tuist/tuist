import FileSystem
import FileSystemTesting
import Foundation
import Testing
@testable import SwifterPMCore

struct NativeRegistryAuthenticationTests {
    @Test(arguments: [
        ("Apple Swift version 6.2.3 (swiftlang-6.2.3)", false),
        ("Swift version 6.3", false),
        ("Swift version 6.3.1", false),
        ("Apple Swift version 6.3.2 (swiftlang-6.3.2)", true),
        ("Swift version 6.4-dev", true),
        ("unrecognized toolchain", false),
    ])
    func upstreamEnvironmentCredentialBoundary(output: String, supported: Bool) {
        #expect(NativeRegistryAuthentication.supportsEnvironmentCredentials(output) == supported)
    }

    @Test
    func serializationPreservesInlineFirstMatchAndExplicitDefault() throws {
        let machines = [
            NetrcMachine(name: "registry.example.com", login: "first", password: "secret"),
            NetrcMachine(name: "registry.example.com", login: "last", password: "wrong"),
            NetrcMachine(name: "other.example.com", login: "space user", password: "se#cret"),
            NetrcMachine(name: "default", login: "fallback", password: "explicit"),
        ]
        let contents = try NativeRegistryAuthentication.serializedInlineNetrc(machines)
        #expect(NetrcParser.machines(in: contents) == [machines[0], machines[2], machines[3]])
        #expect(!contents.contains("wrong"))
    }

    @Test(arguments: ["bad\"secret", "bad\nsecret", "bad\0secret"])
    func unrepresentableSecretsAreRejectedWithoutDisclosure(secret: String) throws {
        let error = #expect(throws: (any Error).self) {
            try NativeRegistryAuthentication.serializedInlineNetrc([
                NetrcMachine(name: "registry.example.com", login: "token", password: secret),
            ])
        }
        #expect(!String(describing: try #require(error)).contains(secret))
    }

    @Test(.inTemporaryDirectory)
    func inlineCredentialsBridgeWithoutRewritingConfiguration() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let config = try await registryConfig(root: root)
        let netrc = inlineNetrc()
        let plan = try NativeRegistryAuthentication.plan(
            versionOutput: "Swift version 6.2.3", environment: inlineEnvironment,
            childEnvironment: inlineEnvironment, netrc: netrc, registryConfig: config
        )
        #expect(plan == .inlineNetrc("machine \"registry.example.com\" login \"token\" password \"secret\"\n"))
        #expect(try await fileSystem.contentsOfDirectory(at: root).map(\.lastPathComponent) == ["registries.json"])
    }

    @Test(.inTemporaryDirectory, arguments: ["SWIFTPM_REGISTRY_TOKEN", "login-password"])
    func originScopedOrGlobalTokensAreNeverConvertedToNetrc(variable: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let config = try await registryConfig(root: root)
        let environment = variable == "login-password"
            ? ["SWIFTPM_REGISTRY_LOGIN": "user", "SWIFTPM_REGISTRY_PASSWORD": "very-secret"]
            : [variable: "very-secret"]
        let error = #expect(throws: (any Error).self) {
            try NativeRegistryAuthentication.plan(
                versionOutput: "Swift version 6.2.3", environment: environment,
                childEnvironment: environment, netrc: .empty, registryConfig: config
            )
        }
        let message = String(describing: try #require(error))
        #expect(message.contains("scope"))
        #expect(!message.contains("very-secret"))
    }

    @Test(.inTemporaryDirectory)
    func sourceControlTokenDoesNotBlockNativeResolutionButCannotBeMergedIntoAnInlineBridge() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let config = try await registryConfig(root: root)
        let token = ["SWIFTPM_SOURCE_CONTROL_TOKEN": "http-secret"]
        #expect(try NativeRegistryAuthentication.plan(
            versionOutput: "Swift version 6.2.3", environment: token,
            childEnvironment: token, netrc: .empty, registryConfig: config
        ) == .native)
        var environment = inlineEnvironment
        environment.merge(token) { _, value in value }
        #expect(throws: (any Error).self) {
            try NativeRegistryAuthentication.plan(
                versionOutput: "Swift version 6.2.3", environment: environment,
                childEnvironment: environment, netrc: inlineNetrc(), registryConfig: config
            )
        }
    }

    @Test(.inTemporaryDirectory, arguments: [true, false])
    func inlineBridgeRejectsEnabledFileCredentials(fileEnabled: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let config = try await registryConfig(root: root)
        let netrc = Netrc(configuration: .init(isEnabled: fileEnabled), sources: [
            NetrcSource(origin: .environment, machines: inlineNetrc().machines(from: .environment)),
            NetrcSource(
                origin: .file,
                machines: [NetrcMachine(name: "artifact.example.com", login: "user", password: "file-secret")]
            ),
        ])
        if fileEnabled {
            #expect(throws: (any Error).self) {
                try NativeRegistryAuthentication.plan(
                    versionOutput: "Swift version 6.2.3", environment: inlineEnvironment,
                    childEnvironment: inlineEnvironment, netrc: netrc, registryConfig: config
                )
            }
        } else {
            let plan = try NativeRegistryAuthentication.plan(
                versionOutput: "Swift version 6.2.3", environment: inlineEnvironment,
                childEnvironment: inlineEnvironment, netrc: netrc, registryConfig: config
            )
            #expect(plan == .inlineNetrc("machine \"registry.example.com\" login \"token\" password \"secret\"\n"))
        }
    }

    @Test(.inTemporaryDirectory)
    func missingNativeAuthenticationTypeFailsBeforeDownloading() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let config = try await registryConfig(root: root, type: nil)
        let error = #expect(throws: (any Error).self) {
            try NativeRegistryAuthentication.plan(
                versionOutput: "Swift version 6.2.3", environment: inlineEnvironment,
                childEnvironment: inlineEnvironment, netrc: inlineNetrc(), registryConfig: config
            )
        }
        #expect(String(describing: try #require(error)).contains("authentication type"))
    }

    @Test(.inTemporaryDirectory, arguments: [true, false])
    func modernToolchainsKeepCredentialsUnlessExplicitlyExcluded(excluded: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let config = try await registryConfig(root: root)
        let environment = ["SWIFTPM_REGISTRY_TOKEN": "secret"]
        if excluded {
            #expect(throws: (any Error).self) {
                try NativeRegistryAuthentication.plan(
                    versionOutput: "Swift version 6.3.2", environment: environment,
                    childEnvironment: [:], netrc: .empty, registryConfig: config
                )
            }
        } else {
            #expect(try NativeRegistryAuthentication.plan(
                versionOutput: "Swift version 6.3.2", environment: environment,
                childEnvironment: environment, netrc: .empty, registryConfig: config
            ) == .native)
        }
    }

    @Test(arguments: ["SWIFTPM_REGISTRY_TOKEN", "SWIFTPM_SOURCE_CONTROL_TOKEN", "SWIFTPM_NETRC_DATA"])
    func unrelatedEnvironmentCredentialsDoNotBlockProjectsWithoutRegistries(variable: String) throws {
        #expect(try NativeRegistryAuthentication.plan(
            versionOutput: "Swift version 6.2.3", environment: [variable: "unrelated"],
            childEnvironment: [:], netrc: inlineNetrc(), registryConfig: RegistryConfig()
        ) == .native)
    }

    @Test(.inTemporaryDirectory)
    func inlineCredentialsForOtherHostsDoNotDisplaceNativeProviders() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let config = try await registryConfig(root: root)
        let netrc = Netrc(sources: [
            NetrcSource(
                origin: .environment,
                machines: [NetrcMachine(name: "artifact.example.com", login: "user", password: "secret")]
            ),
            NetrcSource(origin: .file, machines: [NetrcMachine(name: "registry.example.com", login: "token", password: "file")]),
        ])
        #expect(try NativeRegistryAuthentication.plan(
            versionOutput: "Swift version 6.2.3", environment: inlineEnvironment,
            childEnvironment: inlineEnvironment, netrc: netrc, registryConfig: config
        ) == .native)
    }

    @Test(.inTemporaryDirectory)
    func nativeConfigurationRejectsFilePathsAndPreservesAuthenticationKeyCase() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let file = root.appendingPathComponent("registries.json")
        try await fileSystem.atomicWrite(
            "{\"registries\":{},\"authentication\":{\"REGISTRY.EXAMPLE.COM\":{\"type\":\"token\"}}}", to: file
        )
        await #expect(throws: (any Error).self) {
            try await RegistryConfig.loadForNativeResolution(packageDir: root, configPath: file, defaultRegistryURL: nil)
        }
        let config = try await RegistryConfig.loadForNativeResolution(
            packageDir: root, configPath: root, defaultRegistryURL: "https://registry.example.com"
        )
        #expect(config.authenticationType(for: try #require(URL(string: "https://registry.example.com"))) == nil)
    }

    @Test(.inTemporaryDirectory)
    func nativeConfigurationUsesLocalOverridesAndDoesNotMergeReplacedGlobalConfiguration() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let global = root.appendingPathComponent(".swiftpm/configuration/registries.json")
        let custom = root.appendingPathComponent("custom")
        let package = root.appendingPathComponent("package")
        try await fileSystem.atomicWrite(
            "{\"registries\":{\"global\":{\"url\":\"https://global.example.com\"}}}", to: global
        )
        try await fileSystem.atomicWrite(
            "{\"registries\":{\"example\":{\"url\":\"https://custom.example.com\"}}}",
            to: custom.appendingPathComponent("registries.json")
        )
        try await fileSystem.atomicWrite(
            "{\"registries\":{\"example\":{\"url\":\"https://local.example.com\"}}}",
            to: package.appendingPathComponent(".swiftpm/configuration/registries.json")
        )
        let config = try await Environment.$values.withValue(["HOME": root.path]) {
            try await RegistryConfig.loadForNativeResolution(packageDir: package, configPath: custom, defaultRegistryURL: nil)
        }
        #expect(try config.registryURL(for: "example.package").host == "local.example.com")
        #expect(throws: (any Error).self) { try config.registryURL(for: "global.package") }
    }

    @Test(.inTemporaryDirectory, arguments: [0, 7])
    func credentialOwnerRemovesPrivateFilesOnSuccessAndFailure(status: Int) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let executable = root.appendingPathComponent("native.sh")
        let originalUmask = try await SystemProcess.output("/bin/sh", ["-c", "umask"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #if os(macOS)
            let permissions = "/usr/bin/stat -f '%Lp' \"$3\""
        #else
            let permissions = "/usr/bin/stat -c '%a' \"$3\""
        #endif
        try await fileSystem.atomicWrite(
            """
            test "$1" = --netrc && test "$2" = --netrc-file || exit 1
            printf '%s\\n' "$3" >&2
            \(permissions)
            umask
            exit \(status)
            """,
            to: executable
        )
        var path: String
        do {
            let result = try await SystemProcess.run(
                "/bin/sh", ownerArguments(executable: executable), environment: ["TMPDIR": root.path], input: "dummy secret"
            )
            #expect(status == 0)
            #expect(result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) == "600\n\(originalUmask)")
            path = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            #expect(status != 0)
            path = String(describing: error).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!path.contains("dummy secret"))
        }
        #expect(path.contains("swifterpm-netrc."))
        #expect(!(try await fileSystem.exists(URL(fileURLWithPath: path).deletingLastPathComponent().absolutePath)))
    }

    @Test(.inTemporaryDirectory)
    func credentialOwnerRemovesPrivateFilesOnCancellation() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let executable = root.appendingPathComponent("native.sh")
        let recording = root.appendingPathComponent("netrc-path")
        try await fileSystem.atomicWrite("printf '%s\\n' \"$3\" > \"$4\"\nexec /bin/sleep 30\n", to: executable)
        let arguments = ownerArguments(executable: executable) + [recording.path]
        let task = Task {
            try await SystemProcess.run(
                "/bin/sh", arguments, environment: ["TMPDIR": root.path], input: "dummy secret", gracefulShutdown: true
            )
        }
        do {
            for _ in 0 ..< 100 {
                if try await fileSystem.exists(recording.absolutePath) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let data = try await fileSystem.readFile(at: recording.absolutePath)
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            task.cancel()
            _ = await task.result
            #expect(!(try await fileSystem.exists(URL(fileURLWithPath: path).deletingLastPathComponent().absolutePath)))
        } catch {
            task.cancel()
            _ = await task.result
            throw error
        }
    }

    @Test(.inTemporaryDirectory, arguments: ["INT", "TERM"])
    func credentialOwnerRemovesPrivateFilesOnSignals(signal: String) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory).fileURL
        let executable = root.appendingPathComponent("native.sh")
        let recording = root.appendingPathComponent("netrc-path")
        let ownerPID = root.appendingPathComponent("owner-pid")
        try await fileSystem.atomicWrite(
            "printf '%s\\n' \"$3\" > \"$4\"\nprintf '%s\\n' \"$PPID\" > \"$5\"\nexec /bin/sleep 30\n", to: executable
        )
        let arguments = ownerArguments(executable: executable) + [recording.path, ownerPID.path]
        let task = Task {
            try await SystemProcess.run(
                "/bin/sh", arguments, environment: ["TMPDIR": root.path], input: "dummy secret", gracefulShutdown: true
            )
        }
        do {
            for _ in 0 ..< 100 {
                if try await fileSystem.exists(ownerPID.absolutePath) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let pid = String(decoding: try await fileSystem.readFile(at: ownerPID.absolutePath), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let path = String(decoding: try await fileSystem.readFile(at: recording.absolutePath), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try await SystemProcess.run("/bin/kill", ["-\(signal)", pid])
            if case .success = await task.result { Issue.record("credential owner ignored the signal") }
            #expect(!(try await fileSystem.exists(URL(fileURLWithPath: path).deletingLastPathComponent().absolutePath)))
        } catch {
            task.cancel()
            _ = await task.result
            throw error
        }
    }

    private var inlineEnvironment: [String: String] {
        ["SWIFTPM_NETRC_DATA": "machine registry.example.com login token password secret"]
    }

    private func inlineNetrc() -> Netrc {
        Netrc(sources: [NetrcSource(origin: .environment, machines: [
            NetrcMachine(name: "registry.example.com", login: "token", password: "secret"),
        ])])
    }

    private func registryConfig(root: URL, type: String? = "token") async throws -> RegistryConfig {
        let authentication = type.map { ",\"authentication\":{\"registry.example.com\":{\"type\":\"\($0)\"}}" } ?? ""
        let file = root.appendingPathComponent("registries.json")
        try await fileSystem.atomicWrite(
            "{\"registries\":{\"[default]\":{\"url\":\"https://registry.example.com\"}}\(authentication)}", to: file
        )
        return try await Environment.$values.withValue([:]) {
            try await RegistryConfig.loadForNativeResolution(packageDir: root, configPath: root, defaultRegistryURL: nil)
        }
    }

    private func ownerArguments(executable: URL) -> [String] {
        ["-c", NativeRegistryAuthentication.credentialOwnerScript, "credential-owner", "/bin/sh", executable.path]
    }
}
