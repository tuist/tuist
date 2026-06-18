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

    @Test
    func netrcAuthorizationMatchesHostAndDefault() throws {
        let netrc = RegistryNetrc(
            content: """
            machine registry.example.com login example password secret
            default login fallback password fallback-secret
            """
        )

        #expect(
            netrc.credential(for: try #require(URL(string: "https://registry.example.com")))?
                .password == "secret")
        #expect(
            netrc.credential(for: try #require(URL(string: "https://other.example.com")))?
                .password == "fallback-secret")
    }

    private func uniqueRegistryIdentity() -> String {
        "\(uniqueRegistryScope()).package"
    }

    private func uniqueRegistryScope() -> String {
        "scope\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased())"
    }

    private func registryConfig() async throws -> RegistryConfig {
        try await withTemporaryDirectory { root in
            try await RegistryConfig.load(
                packageDir: root,
                configPath: nil,
                defaultRegistryURL: "https://registry.example.com"
            )
        }
    }
}
