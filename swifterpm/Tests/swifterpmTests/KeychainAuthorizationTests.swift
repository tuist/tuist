import FileSystem
import FileSystemTesting
import Foundation
import Synchronization
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

        @Test(arguments: [true, false], [true, false])
        func headlessReadsRestoreThePreviousInteractionSetting(previous: Bool, denied: Bool) throws {
            var allowed = previous
            var events: [String] = []
            let operation = {
                try KeychainCredentialReader.withInteractionPolicy(
                    headless: true, host: "registry.example.com",
                    getInteraction: { events.append("get"); return (errSecSuccess, allowed) },
                    setInteraction: { allowed = $0; events.append("set:\($0)"); return errSecSuccess }
                ) {
                    events.append("read")
                    #expect(!allowed)
                    if denied {
                        throw KeychainAuthorization.AccessFailure(status: errSecAuthFailed, host: "registry.example.com")
                    }
                    return RegistryCredential(user: "token", password: "fixture-secret")
                }
            }
            if denied {
                #expect(throws: KeychainAuthorization.AccessFailure.self) { try operation() }
            } else {
                #expect(try operation().password == "fixture-secret")
            }
            #expect(allowed == previous)
            #expect(events == ["get", "set:false", "read", "set:\(previous)"])
        }

        @Test
        func interactiveReadsLeaveTheInteractionPolicyUntouched() throws {
            let value = try KeychainCredentialReader.withInteractionPolicy(
                headless: false, host: "registry.example.com",
                getInteraction: { Issue.record("interactive read queried interaction policy"); return (errSecSuccess, true) },
                setInteraction: { _ in Issue.record("interactive read changed interaction policy"); return errSecSuccess }
            ) { "credential" }
            #expect(value == "credential")
        }

        @Test(arguments: [true, false])
        func policyFailuresDoNotAttemptAPossiblyInteractiveLookup(getFails: Bool) throws {
            #expect(throws: KeychainCredentialReader.InfrastructureFailure.self) {
                try KeychainCredentialReader.withInteractionPolicy(
                    headless: true, host: "registry.example.com",
                    getInteraction: { (getFails ? errSecNotAvailable : errSecSuccess, true) },
                    setInteraction: { _ in errSecNotAvailable }
                ) { Issue.record("lookup attempted without disabling UI") }
            }
        }

        @Test
        func cancellationStillRestoresTheInteractionSetting() throws {
            var allowed = true
            #expect(throws: CancellationError.self) {
                try KeychainCredentialReader.withInteractionPolicy(
                    headless: true, host: "registry.example.com",
                    getInteraction: { (errSecSuccess, allowed) },
                    setInteraction: { allowed = $0; return errSecSuccess }
                ) { throw CancellationError() }
            }
            #expect(allowed)
        }

        @Test
        func concurrentPolicyChangesDoNotOverlap() {
            let events = WarningRecorder()
            DispatchQueue.concurrentPerform(iterations: 20) { index in
                do {
                    try KeychainCredentialReader.withInteractionPolicy(
                        headless: true, host: "registry.example.com",
                        getInteraction: { events.messages.withLock { $0.append("\(index):get") }; return (errSecSuccess, true) },
                        setInteraction: { allowed in
                            events.messages.withLock { $0.append("\(index):set:\(allowed)") }
                            return errSecSuccess
                        }
                    ) { events.messages.withLock { $0.append("\(index):read") } }
                } catch { Issue.record(error) }
            }
            let recorded = events.messages.withLock { $0 }
            #expect(recorded.count == 80)
            for offset in stride(from: 0, to: recorded.count, by: 4) {
                let index = recorded[offset].split(separator: ":")[0]
                #expect(Array(recorded[offset ..< offset + 4]) == [
                    "\(index):get",
                    "\(index):set:false",
                    "\(index):read",
                    "\(index):set:true",
                ])
            }
        }

        @Test(arguments: [true, false])
        func restoreFailureDoesNotHideAnActualAccessDenial(denied: Bool) throws {
            let error = #expect(throws: (any Error).self) {
                try Environment.$warningHandler.withValue(nil) {
                    try KeychainCredentialReader.withInteractionPolicy(
                        headless: true, host: "registry.example.com",
                        getInteraction: { (errSecSuccess, true) },
                        setInteraction: { $0 ? errSecNotAvailable : errSecSuccess }
                    ) {
                        if denied { throw KeychainAuthorization.AccessFailure(
                            status: errSecAuthFailed,
                            host: "registry.example.com"
                        ) }
                    }
                }
            }
            if denied { #expect(error is KeychainAuthorization.AccessFailure) }
            else { #expect(error is KeychainCredentialReader.InfrastructureFailure) }
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
        func httpUnexpectedFailuresDoNotBlockPublicDownloadsOrExposeDetails() async throws {
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
        func registryPolicyInfrastructureFailureAllowsAnonymousRequestsButAccessDenialRemainsStrict() async throws {
            let url = try #require(URL(string: "https://registry.example.com"))
            var warning = ""
            let credential = try await KeychainAuthorization.registryCredential(
                for: url,
                read: { _ in throw KeychainCredentialReader.InfrastructureFailure(host: "registry.example.com") },
                warning: { warning = $0 }
            )
            #expect(credential == nil)
            #expect(warning.contains("unauthenticated registry request"))
            await #expect(throws: KeychainAuthorization.AccessFailure.self) {
                try await KeychainAuthorization.registryCredential(
                    for: url,
                    read: { _ in throw KeychainAuthorization.AccessFailure(status: errSecAuthFailed, host: url.host) }
                )
            }
        }

        @Test(arguments: [true, false])
        func warningsUseRuntimeCallbackAndHonorQuiet(quiet: Bool) async throws {
            let warnings = WarningRecorder()
            await SwifterPM.withWarningHandler({ message in warnings.messages.withLock { $0.append(message) } }) {
                await Environment.withWarnings(quiet: quiet) { Environment.warningHandler?("fixture warning") }
            }
            #expect(warnings.messages.withLock { $0 } == (quiet ? [] : ["fixture warning"]))
        }

        @Test
        func cancellingLastWaiterCancelsReadAndDoesNotCacheCancellation() async throws {
            let cache = KeychainCredentialCache()
            let started = LookupCounter()
            let url = try #require(URL(string: "https://registry.example.com"))
            let caller = Task {
                try await cache.credential(for: url) { _ in
                    _ = await started.read(url)
                    try await Task.sleep(for: .seconds(30))
                    return nil
                }
            }
            while await started.count == 0 {
                await Task.yield()
            }
            caller.cancel()
            await #expect(throws: CancellationError.self) { try await caller.value }
            let result = try await cache.credential(for: url) { _ in RegistryCredential(user: "token", password: "new") }
            #expect(result?.password == "new")
        }

        @Test
        func cancellingOneWaiterDoesNotCancelAnotherSharedRead() async throws {
            let cache = KeychainCredentialCache()
            let started = LookupCounter()
            let gate = ReadGate()
            let url = try #require(URL(string: "https://registry.example.com"))
            let reader: @Sendable (URL) async throws -> RegistryCredential? = { url in
                _ = await started.read(url)
                await gate.wait()
                return RegistryCredential(user: "token", password: "shared")
            }
            let first = Task { try await cache.credential(for: url, read: reader) }
            let second = Task { try await cache.credential(for: url, read: reader) }
            while await cache.pendingWaiterCount != 2 {
                await Task.yield()
            }
            first.cancel()
            await #expect(throws: CancellationError.self) { try await first.value }
            await gate.release()
            #expect(try await second.value?.password == "shared")
            #expect(await started.count == 1)
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

        private actor ReadGate {
            private var continuation: CheckedContinuation<Void, Never>?
            private var released = false

            func wait() async {
                if released { return }
                await withCheckedContinuation { continuation = $0 }
            }

            func release() {
                released = true
                continuation?.resume()
                continuation = nil
            }
        }

        private final class WarningRecorder: Sendable {
            let messages = Mutex([String]())
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
