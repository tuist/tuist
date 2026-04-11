import ArgumentParser
import Foundation

public enum TestProcessingMode: String, Sendable, CaseIterable, ExpressibleByArgument {
    case local
    case remote

    /// Returns the default processing mode for the given Tuist server URL.
    ///
    /// Defaults to `.remote` for the official Tuist hosts (`tuist.dev`, `staging.tuist.dev`,
    /// `canary.tuist.dev`) and for `localhost`. All other URLs default to `.local` so
    /// self-hosted instances continue to parse xcresults locally unless explicitly opted in.
    public static func `default`(for url: URL) -> TestProcessingMode {
        let knownRemoteHosts: Set<String> = [
            "tuist.dev",
            "staging.tuist.dev",
            "canary.tuist.dev",
            "localhost",
        ]
        if let host = url.host, knownRemoteHosts.contains(host) {
            return .remote
        }
        return .local
    }
}
