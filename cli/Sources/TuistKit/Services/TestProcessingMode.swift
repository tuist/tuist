import ArgumentParser
import Foundation

public enum TestProcessingMode: String, Sendable, CaseIterable, ExpressibleByArgument {
    case local
    case remote

    /// Returns the default processing mode for the given Tuist server URL.
    ///
    /// Defaults to `.remote` for tuist-hosted instances and `.local` for self-hosted ones,
    /// so self-hosted servers keep parsing xcresults locally unless they explicitly opt in.
    public static func `default`(for url: URL) -> TestProcessingMode {
        let tuistHostedHosts: Set<String> = [
            "tuist.dev",
            "staging.tuist.dev",
            "canary.tuist.dev",
            "localhost",
        ]
        if let host = url.host, tuistHostedHosts.contains(host) {
            return .remote
        }
        return .local
    }
}
