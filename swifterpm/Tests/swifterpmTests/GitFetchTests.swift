import Foundation
import Testing
@testable import SwifterPMCore

struct GitFetchTests {
    @Test
    func retriesTheSameCandidateAnonymouslyWhenTheCredentialIsRejected() async throws {
        try await withTemporaryDirectory { root in
            try await withLocalGitHTTPServer(root: root, repository: "repo.git", tag: "1.0.0") {
                server in
                let location = server.url(path: "/repo.git")
                let credential = Data("x-access-token:not-a-github-com-token".utf8)
                    .base64EncodedString()
                let configArguments = [
                    "-c", "http.\(server.baseURL).extraheader=Authorization: Basic \(credential)",
                ]

                let attempted = Attempted()
                let output = try await GitFetch.perform(
                    GitFetch.attempts(for: location, authenticatedWith: configArguments),
                    for: location
                ) { attempt in
                    attempted.record(attempt)
                    return try await SystemProcess.output(
                        "/usr/bin/git",
                        attempt.configArguments + ["ls-remote", "--tags", attempt.location],
                        environment: SystemProcess.nonInteractiveGitEnvironment
                    )
                }

                #expect(output.contains("refs/tags/1.0.0"))
                #expect(attempted.configArguments == [configArguments, []])
                #expect(server.authenticatedRequests.isEmpty == false)
                #expect(server.anonymousRequests.isEmpty == false)
            }
        }
    }

    @Test
    func attemptsACandidateOnlyOnceWhenItCarriesNoCredential() {
        #expect(
            GitFetch.attempts(
                for: "git@github.com:acme/private-lib.git", authenticatedWith: []
            )
            .map(\.configArguments) == [[]]
        )
    }

    @Test
    func attemptsACredentialledCandidateAnonymouslyBeforeMovingOn() {
        let configArguments = ["-c", "http.https://github.com/.extraheader=Authorization: Basic x"]
        let attempts = GitFetch.attempts(
            for: "https://github.com/acme/public-lib.git", authenticatedWith: configArguments
        )

        #expect(attempts.map(\.location) == Array(repeating: "https://github.com/acme/public-lib.git", count: 2))
        #expect(attempts.map(\.configArguments) == [configArguments, []])
    }

    @Test
    func failureReportsEachCandidateOnceWhenDroppingTheCredentialChangesNothing() {
        let error = GitFetchFailure.error(
            location: "https://github.com/acme/lib",
            failures: [
                failure("https://github.com/acme/lib", authenticated: true, "repository not found"),
                failure("https://github.com/acme/lib", authenticated: false, "repository not found"),
                failure("git@github.com:acme/lib.git", authenticated: false, "Host key verification failed."),
            ]
        )

        #expect(
            "\(error)" == """
            could not fetch any candidate location for https://github.com/acme/lib:
              - https://github.com/acme/lib: repository not found
              - git@github.com:acme/lib.git: Host key verification failed.
            """
        )
    }

    @Test
    func failureDistinguishesTheAnonymousRetryWhenItFailedDifferently() {
        let error = GitFetchFailure.error(
            location: "https://github.com/acme/lib",
            failures: [
                failure("https://github.com/acme/lib", authenticated: true, "terminal prompts disabled"),
                failure("https://github.com/acme/lib", authenticated: false, "repository not found"),
            ]
        )

        #expect(
            "\(error)" == """
            could not fetch any candidate location for https://github.com/acme/lib:
              - https://github.com/acme/lib: terminal prompts disabled
              - https://github.com/acme/lib (unauthenticated): repository not found
            """
        )
    }

    private func failure(_ location: String, authenticated: Bool, _ message: String)
        -> GitFetchAttemptFailure
    {
        GitFetchAttemptFailure(
            attempt: GitFetchAttempt(
                location: location,
                configArguments: authenticated ? ["-c", "http.extraheader=Authorization: Basic x"] : []
            ),
            error: ToolError.message(message)
        )
    }
}

private final class Attempted: @unchecked Sendable {
    private(set) var configArguments: [[String]] = []

    func record(_ attempt: GitFetchAttempt) {
        configArguments.append(attempt.configArguments)
    }
}
