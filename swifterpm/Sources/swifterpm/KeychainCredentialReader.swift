import Foundation
import Synchronization
#if canImport(Security)
    import Security
#endif

/// Legacy keychain approval is process-wide. Serialize our synchronous reads and
/// restore the caller's setting before leaving the headless lookup, even on failure.
enum KeychainCredentialReader {
    struct InfrastructureFailure: Error, CustomStringConvertible {
        let host: String
        var description: String { "failed to perform a noninteractive keychain lookup for \(host)" }
    }

    #if canImport(Security)
        private static let interactionLock = Mutex<Void>(())

        static func withInteractionPolicy<T>(
            headless: Bool,
            host: String?,
            getInteraction: () -> (OSStatus, Bool) = {
                var allowed = DarwinBoolean(false)
                let status = SecKeychainGetUserInteractionAllowed(&allowed)
                return (status, allowed.boolValue)
            },
            setInteraction: (Bool) -> OSStatus = { SecKeychainSetUserInteractionAllowed($0) },
            operation: () throws -> T
        ) throws -> T {
            try interactionLock.withLock { _ in
                guard headless else { return try operation() }
                let (status, previous) = getInteraction()
                guard status == errSecSuccess, setInteraction(false) == errSecSuccess else {
                    throw InfrastructureFailure(host: host ?? "the download host")
                }
                let result = Result(catching: operation)
                if setInteraction(previous) != errSecSuccess {
                    // Preserve an actual access denial if restoring the policy also fails.
                    if case .success = result {
                        throw InfrastructureFailure(host: host ?? "the download host")
                    }
                    Environment.warningHandler?("failed to restore the previous keychain interaction setting")
                }
                return try result.get()
            }
        }
    #endif
}

extension SwifterPM {
    public static func withWarningHandler<T>(
        _ warning: @escaping @Sendable (String) -> Void,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await Environment.$warningHandler.withValue(warning) { try await operation() }
    }
}
