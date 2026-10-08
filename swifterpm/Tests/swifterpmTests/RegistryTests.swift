import Foundation
import Testing
@testable import SwifterPMCore

struct RegistryTests {
    @Test
    func loadUsesProvidedDefaultRegistryURL() async throws {
        try await withTemporaryDirectory { root in
            let config = try await RegistryConfig.load(
                packageDir: root,
                configPath: nil,
                defaultRegistryURL: "https://registry.example.com"
            )

            #expect(
                try config.registryURL(for: uniqueRegistryIdentity()).absoluteString
                    == "https://registry.example.com")
        }
    }

    @Test
    func loadReadsPackageScopedRegistryConfig() async throws {
        try await withTemporaryDirectory { root in
            let scope = uniqueRegistryScope()
            let registries = root.appendingPathComponent(".swiftpm/configuration/registries.json")
            try await fileSystem.atomicWrite(
                """
                {
                  "registries": {
                    "\(scope)": {
                      "url": "https://\(scope).example.com"
                    }
                  }
                }
                """,
                to: registries
            )

            let config = try await RegistryConfig.load(
                packageDir: root, configPath: nil, defaultRegistryURL: nil)

            #expect(
                try config.registryURL(for: "\(scope).package").absoluteString
                    == "https://\(scope).example.com")
        }
    }

    @Test
    func registryAuthorizationUsesBearerForTokenUserByDefault() async throws {
        let config = try await registryConfig()
        let header = RegistryAuthorization.header(
            for: RegistryCredential(user: "token", password: "secret"),
            url: try #require(URL(string: "https://registry.example.com")),
            registryConfig: config
        )

        #expect(header == "Bearer secret")
    }

    @Test
    func registryAuthorizationUsesBasicForLoginPasswordByDefault() async throws {
        let config = try await registryConfig()
        let header = RegistryAuthorization.header(
            for: RegistryCredential(user: "user", password: "secret"),
            url: try #require(URL(string: "https://registry.example.com")),
            registryConfig: config
        )

        #expect(header == "Basic dXNlcjpzZWNyZXQ=")
    }

    @Test
    func registryAuthorizationHonorsConfiguredTokenAuthentication() async throws {
        try await withTemporaryDirectory { root in
            let registries = root.appendingPathComponent(".swiftpm/configuration/registries.json")
            try await fileSystem.atomicWrite(
                """
                {
                  "registries": {
                    "[default]": {
                      "url": "https://registry.example.com"
                    }
                  },
                  "authentication": {
                    "registry.example.com": {
                      "type": "token"
                    }
                  }
                }
                """,
                to: registries
            )
            let config = try await RegistryConfig.load(
                packageDir: root, configPath: nil, defaultRegistryURL: nil)

            let header = RegistryAuthorization.header(
                for: RegistryCredential(user: "user", password: "secret"),
                url: try #require(URL(string: "https://registry.example.com")),
                registryConfig: config
            )

            #expect(header == "Bearer secret")
        }
    }

    @Test(arguments: [nil, "basic", "token"] as [String?])
    func environmentTokenHonorsConfiguredAuthentication(type: String?) async throws {
        let config = try await registryConfig(authenticationType: type)
        let header = try await Environment.$values.withValue([
            "SWIFTPM_REGISTRY_TOKEN": "secret",
            "SWIFTPM_REGISTRY_LOGIN": "ignored", "SWIFTPM_REGISTRY_PASSWORD": "ignored",
        ]) {
            await RegistryAuthorization.header(
                for: try #require(URL(string: "https://registry.example.com/path")),
                registryConfig: config,
                keychain: { _ in Issue.record("keychain consulted despite environment token"); return nil }
            )
        }
        let expected = type == "basic"
            ? "Basic " + Data("token:secret".utf8).base64EncodedString() : "Bearer secret"
        #expect(header == expected)
    }

    @Test(arguments: [
        "https://unconfigured.example.com", "https://registry.example.com:8443",
        "http://registry.example.com",
    ])
    func environmentCredentialsAreScopedToRegistryOriginsWithoutFallback(location: String) async throws {
        let config = try await registryConfig()
        let netrc = Netrc(configuration: .init(forcesNetrc: true), sources: [
            NetrcSource(origin: .file, machines: [NetrcMachine(name: "default", login: "file", password: "secret")]),
        ])
        let header = try await Environment.$values.withValue(["SWIFTPM_REGISTRY_TOKEN": "secret"]) {
            try await Environment.withNetrc(netrc) {
                await RegistryAuthorization.header(
                    for: try #require(URL(string: location)), registryConfig: config,
                    keychain: { _ in Issue.record("keychain consulted despite environment provider"); return nil }
                )
            }
        }
        #expect(header == nil)
    }

    @Test(arguments: [true, false])
    func environmentLoginRequiresBothCredentials(hasPassword: Bool) async throws {
        let config = try await registryConfig()
        let netrc = Netrc(configuration: .init(forcesNetrc: true), sources: [
            NetrcSource(origin: .file, machines: [
                NetrcMachine(name: "registry.example.com", login: "file", password: "credential"),
            ]),
        ])
        var environment = ["SWIFTPM_REGISTRY_LOGIN": "user"]
        if hasPassword { environment["SWIFTPM_REGISTRY_PASSWORD"] = "secret" }
        let header = try await Environment.$values.withValue(environment) {
            try await Environment.withNetrc(netrc) {
                await RegistryAuthorization.header(
                    for: try #require(URL(string: "https://registry.example.com")), registryConfig: config,
                    keychain: { _ in nil }
                )
            }
        }
        let credential = hasPassword ? "user:secret" : "file:credential"
        #expect(header == "Basic " + Data(credential.utf8).base64EncodedString())
    }

    @Test(arguments: ["inline-miss", "keychain-miss", "forced-file", "disabled-file", "disabled-inline"])
    func registryProviderSelectionMatchesNative(mode: String) async throws {
        let config = try await registryConfig()
        var sources = [NetrcSource(origin: .file, machines: [
            NetrcMachine(name: "registry.example.com", login: "file", password: "credential"),
        ])]
        if mode == "inline-miss" || mode == "disabled-inline" {
            sources.insert(NetrcSource(origin: .environment, machines: [
                NetrcMachine(
                    name: mode == "inline-miss" ? "other.example.com" : "registry.example.com",
                    login: "inline", password: "credential"
                ),
            ]), at: 0)
        }
        let netrc = Netrc(configuration: .init(
            isEnabled: !mode.hasPrefix("disabled"),
            forcesNetrc: mode == "forced-file" || mode == "disabled-file",
            disableKeychain: true
        ), sources: sources)
        let header = try await Environment.$values.withValue([:]) {
            try await Environment.withNetrc(netrc) {
                await RegistryAuthorization.header(
                    for: try #require(URL(string: "https://registry.example.com")), registryConfig: config,
                    keychain: { _ in nil }
                )
            }
        }
        switch mode {
        case "inline-miss": #expect(header == nil)
        case "keychain-miss":
            #expect(header == (KeychainAuthorization.isSupported ? nil : "Basic ZmlsZTpjcmVkZW50aWFs"))
        case "disabled-inline": #expect(header == "Basic aW5saW5lOmNyZWRlbnRpYWw=")
        default: #expect(header == "Basic ZmlsZTpjcmVkZW50aWFs")
        }
    }

    private func uniqueRegistryIdentity() -> String {
        "\(uniqueRegistryScope()).package"
    }

    private func uniqueRegistryScope() -> String {
        "scope\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased())"
    }

    private func registryConfig(authenticationType: String? = nil) async throws -> RegistryConfig {
        try await withTemporaryDirectory { root in
            if let authenticationType {
                try await fileSystem.atomicWrite(
                    """
                    {"registries": {}, "authentication": {"registry.example.com": {"type": "\(authenticationType)"}}}
                    """,
                    to: root.appendingPathComponent("registries.json")
                )
            }
            return try await Environment.$values.withValue([:]) {
                try await RegistryConfig.load(
                    packageDir: root,
                    configPath: authenticationType == nil ? nil : root.appendingPathComponent("registries.json"),
                    defaultRegistryURL: "https://registry.example.com"
                )
            }
        }
    }
}
