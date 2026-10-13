import Foundation
import Testing
@testable import SwifterPMCore

#if canImport(Security)
    import Security

    struct KeychainAuthorizationTests {
        @Test(arguments: [true, false])
        func queriesMatchNativeAttributesWithoutCredentialURLs(includeData: Bool) throws {
            let url = try #require(URL(string: "https://user:secret@registry.example.com:8443/path?token=secret"))
            let query = try #require(KeychainAuthorization.query(for: url, includeData: includeData))
            #expect(query[kSecAttrServer as String] as? String == "registry.example.com")
            #expect(query[kSecAttrPort as String] as? Int == 8443)
            #expect(query[kSecReturnData as String] as? Bool == (includeData ? true : nil))
        }

        @Test
        func isolatedReaderDoesNotChangeCallingProcessInteractionPolicy() async throws {
            var before = DarwinBoolean(false)
            #expect(SecKeychainGetUserInteractionAllowed(&before) == errSecSuccess)
            let host = "swifterpm-\(UUID().uuidString.lowercased()).invalid"
            do {
                let credential = try await KeychainCredentialReader.credential(for: try #require(URL(string: "https://\(host)")))
                #expect(credential == nil)
            } catch let failure as KeychainAuthorization.AccessFailure {
                // A locked search-list keychain may prevent even searching for a missing host.
                #expect(failure.status == errSecInteractionNotAllowed || failure.status == errSecNotAvailable)
            }
            var after = DarwinBoolean(false)
            #expect(SecKeychainGetUserInteractionAllowed(&after) == errSecSuccess)
            #expect(before.boolValue == after.boolValue)
        }

        @Test
        func isolatedReaderDecodesCredentialsAndRedactsMalformedReplies() throws {
            let data = Data("{\"status\":0,\"user\":\"token\",\"password\":\"fixture-secret\"}".utf8)
            let credential = try #require(try KeychainCredentialReader.decodeReply(data, host: "registry.example.com"))
            #expect(credential.user == "token")
            #expect(credential.password == "fixture-secret")
            for reply in ["not-json fixture-secret", "{\"status\":0,\"password\":\"fixture-secret\"}"] {
                let error = #expect(throws: (any Error).self) {
                    try KeychainCredentialReader.decodeReply(Data(reply.utf8), host: "registry.example.com")
                }
                #expect(!String(describing: try #require(error)).contains("fixture-secret"))
            }
        }

        @Test
        func missingCredentialsAreNotAnAccessFailure() throws {
            #expect(try KeychainAuthorization.lookupSucceeded(errSecSuccess, host: "registry.example.com"))
            #expect(try !KeychainAuthorization.lookupSucceeded(errSecItemNotFound, host: "registry.example.com"))
        }

        @Test(arguments: [errSecInteractionNotAllowed, errSecAuthFailed, errSecNotAvailable])
        func accessFailuresAreActionable(status: OSStatus) throws {
            let error = #expect(throws: (any Error).self) {
                try KeychainAuthorization.lookupSucceeded(status, host: "registry.example.com")
            }
            let message = String(describing: try #require(error))
            #expect(message.contains("keychain"))
            #expect(message.contains("--netrc --netrc-file"))
            #expect(message.contains("registry.example.com"))
        }

        @Test
        func registryKeychainFailureDoesNotFallThroughToFileCredentials() async throws {
            await #expect(throws: (any Error).self) {
                try await RegistryAuthorization.prioritizedCredential(
                    environmentNetrcIsConfigured: false, environmentNetrc: nil,
                    fileNetrc: RegistryCredential(user: "token", password: "file-secret"),
                    usesKeychain: true,
                    keychain: {
                        _ = try KeychainAuthorization.lookupSucceeded(errSecInteractionNotAllowed, host: "registry.example.com")
                        return nil
                    }
                )
            }
        }

        @Test
        func httpAccessFailureWarnsAndAllowsPublicDownloads() async throws {
            var warning = ""
            let credential = try await KeychainAuthorization.httpCredential(
                for: try #require(URL(string: "https://github.com/public/archive.zip")),
                read: { _ in throw KeychainAuthorization.AccessFailure(status: errSecInteractionNotAllowed, host: "github.com") },
                warning: { warning = $0 }
            )
            #expect(credential == nil)
            #expect(warning.contains("without keychain credentials"))
            #expect(warning.contains("github.com"))
        }

        @Test
        func httpReaderStartupFailuresDoNotBlockPublicDownloadsOrExposeOutput() async throws {
            var warning = ""
            let credential = try await KeychainAuthorization.httpCredential(
                for: try #require(URL(string: "https://github.com/public/archive.zip")),
                read: { _ in throw ToolError.message("malformed-secret-reply") },
                warning: { warning = $0 }
            )
            #expect(credential == nil)
            #expect(warning.contains("without keychain credentials"))
            #expect(!warning.contains("malformed-secret-reply"))
        }

        @Test
        func concurrentReadsShareOneLookupButPreserveExplicitPorts() async throws {
            let cache = KeychainCredentialCache()
            let counter = LookupCounter()
            let url = try #require(URL(string: "https://registry.example.com"))
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 8 {
                    group.addTask {
                        _ = try await cache.credential(for: url) { await counter.read($0) }
                    }
                }
                try await group.waitForAll()
            }
            #expect(await counter.count == 1)
            _ = try await cache.credential(for: try #require(URL(string: "https://registry.example.com:443"))) {
                await counter.read($0)
            }
            #expect(await counter.count == 2)
        }

        @Test
        func subprocessFailureRedactsPartialCredentialOutput() async throws {
            let error = await #expect(throws: (any Error).self) {
                try await SystemProcess.run(
                    "/bin/sh", ["-c", "printf 'sensitive-credential'; exit 1"], failureMessage: "keychain lookup failed"
                )
            }
            #expect(String(describing: try #require(error)) == "keychain lookup failed")
        }

        private actor LookupCounter {
            private(set) var count = 0

            func read(_: URL) -> RegistryCredential? {
                count += 1
                return RegistryCredential(user: "token", password: "fixture-secret")
            }
        }
    }
#endif
