import Foundation

/// One attempt at reaching a package's source control: a candidate location paired with the
/// `git -c` arguments that authenticate it, empty when the attempt is anonymous.
struct GitFetchAttempt {
    let location: String
    let configArguments: [String]

    var isAuthenticated: Bool { !configArguments.isEmpty }
}

struct GitFetchAttemptFailure {
    let attempt: GitFetchAttempt
    let error: any Error
}

/// Drives the ordered attempts a git operation makes to reach a package.
///
/// Every candidate that carries a credential is also attempted anonymously before the next
/// candidate is tried. github.com answers a credential it does not accept with a 401 rather
/// than serving a public repository anonymously, git then asks for a username, and
/// `GIT_TERMINAL_PROMPT=0` turns that question into a hard failure. Without the anonymous
/// retry an ambient token that does not belong to the host, such as the one GitHub Actions
/// exports on a runner attached to a GitHub Enterprise Server instance, makes a dependency
/// that plain `git clone` would have fetched unfetchable.
enum GitFetch {
    static func attempts(for location: String) async -> [GitFetchAttempt] {
        var attempts: [GitFetchAttempt] = []
        for candidate in SourceControlLocations.fetchCandidates(location) {
            let configArguments = await GitTransportAuth.configArguments(for: candidate)
            attempts.append(
                contentsOf: Self.attempts(for: candidate, authenticatedWith: configArguments)
            )
        }
        return attempts
    }

    static func attempts(for candidate: String, authenticatedWith configArguments: [String])
        -> [GitFetchAttempt]
    {
        let authenticated = GitFetchAttempt(location: candidate, configArguments: configArguments)
        guard authenticated.isAuthenticated else { return [authenticated] }
        return [authenticated, GitFetchAttempt(location: candidate, configArguments: [])]
    }

    static func perform<T>(
        _ attempts: [GitFetchAttempt],
        for location: String,
        operation: (GitFetchAttempt) async throws -> T
    ) async throws -> T {
        var failures: [GitFetchAttemptFailure] = []
        for attempt in attempts {
            do {
                return try await operation(attempt)
            } catch {
                failures.append(GitFetchAttemptFailure(attempt: attempt, error: error))
            }
        }
        throw GitFetchFailure.error(location: location, failures: failures)
    }

    static func withAttempts<T>(
        for location: String,
        operation: (GitFetchAttempt) async throws -> T
    ) async throws -> T {
        try await perform(await attempts(for: location), for: location, operation: operation)
    }
}

/// Reports every attempt that was made and how each failed. Reporting only the last error
/// would surface the trailing SSH candidate for an SSH-declared dependency, masking whether
/// the HTTPS fallback was attempted at all and why it failed.
enum GitFetchFailure {
    static func error(location: String, failures: [GitFetchAttemptFailure]) -> ToolError {
        guard !failures.isEmpty else {
            return ToolError.message("no source-control locations available for \(location)")
        }
        let details = reported(failures)
            .map { "  - \($0.label): \($0.description)" }
            .joined(separator: "\n")
        return ToolError.message(
            "could not fetch any candidate location for \(location):\n\(details)"
        )
    }

    private struct ReportedFailure {
        let label: String
        let description: String
    }

    /// A candidate is attempted twice whenever it carries a credential, so reporting every
    /// attempt verbatim would list most candidates twice for the same reason. Repeats of a
    /// description a candidate already reported are dropped, and only a genuinely different
    /// outcome from dropping the credential earns its own line.
    private static func reported(_ failures: [GitFetchAttemptFailure]) -> [ReportedFailure] {
        var reported: [ReportedFailure] = []
        for candidate in candidates(of: failures) {
            var descriptions: Set<String> = []
            for failure in failures where failure.attempt.location == candidate {
                let description = "\(failure.error)"
                guard descriptions.insert(description).inserted else { continue }
                let label = descriptions.count == 1 ? candidate : "\(candidate) (unauthenticated)"
                reported.append(ReportedFailure(label: label, description: description))
            }
        }
        return reported
    }

    private static func candidates(of failures: [GitFetchAttemptFailure]) -> [String] {
        var candidates: [String] = []
        for failure in failures where !candidates.contains(failure.attempt.location) {
            candidates.append(failure.attempt.location)
        }
        return candidates
    }
}
