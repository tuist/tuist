import Foundation
import Testing
@testable import SwifterPMCore

/// Attempt ordering is decided by reading the developer's own git configuration, so every
/// test that exercises it pins that configuration instead of inheriting the machine's.
func withGitConfiguration<T: Sendable>(
    _ configuration: GitConfiguration,
    environment: [String: String] = [:],
    operation: () async -> T
) async -> T {
    await Environment.$gitConfiguration.withValue(configuration) {
        await Environment.$values.withValue(environment) {
            await operation()
        }
    }
}

extension GitConfiguration {
    /// What Apple's toolchain ships on every developer Mac: an unscoped helper, which
    /// answers for every host.
    static let osxkeychain = GitConfiguration(
        insteadOfPrefixes: [], hasUnscopedHelper: true, helperURLs: []
    )
}

extension Netrc {
    /// `SWIFTPM_NETRC_DATA` or a `--netrc-file`, neither of which curl reads for git.
    static let invisibleToGit = Netrc(sources: [
        NetrcSource(
            origin: .environment,
            machines: [NetrcMachine(name: "github.com", login: "machine-user", password: "s3cret")]
        ),
    ])

    /// `~/.netrc`, the one netrc source git authenticates with by itself.
    static let visibleToGit = Netrc(sources: [
        NetrcSource(
            origin: .file,
            machines: [NetrcMachine(name: "github.com", login: "machine-user", password: "s3cret")],
            isGitVisible: true
        ),
    ])
}

struct GitHubTests {
    @Test
    func parsesHTTPSGitHubLocations() throws {
        let repo = try GitHubRepo(location: "https://github.com/tuist/swifterpm.git")

        #expect(repo.owner == "tuist")
        #expect(repo.repo == "swifterpm")
    }

    @Test
    func parsesSSHGitHubLocations() throws {
        let repo = try GitHubRepo(location: "git@github.com:tuist/swifterpm.git")

        #expect(repo.owner == "tuist")
        #expect(repo.repo == "swifterpm")
    }

    @Test
    func rejectsNonGitHubLocations() {
        #expect(throws: (any Error).self) {
            try GitHubRepo(location: "https://gitlab.com/tuist/swifterpm")
        }
    }

    @Test
    func sourceControlFetchLocationsPreferOriginalThenProviderAlternatives() {
        #expect(
            SourceControlLocations.fetchCandidates("https://github.com/tuist/swifterpm") == [
                "https://github.com/tuist/swifterpm",
                "https://github.com/tuist/swifterpm.git",
                "git@github.com:tuist/swifterpm.git",
            ]
        )
        #expect(
            SourceControlLocations.fetchCandidates("git@github.com:tuist/swifterpm.git") == [
                "git@github.com:tuist/swifterpm.git",
                "https://github.com/tuist/swifterpm.git",
            ]
        )
        #expect(
            SourceControlLocations.fetchCandidates("https://gitlab.com/tuist/swifterpm") == [
                "https://gitlab.com/tuist/swifterpm",
                "https://gitlab.com/tuist/swifterpm.git",
                "git@gitlab.com:tuist/swifterpm.git",
            ]
        )
    }

    @Test
    func sourceControlFetchLocationsAddHTTPSFallbackForSSHOrigin() {
        #expect(
            SourceControlLocations.fetchCandidates(
                "git@github.com:acme/private-lib"
            ) == [
                "git@github.com:acme/private-lib",
                "https://github.com/acme/private-lib.git",
                "git@github.com:acme/private-lib.git",
            ]
        )
    }

    @Test
    func gitHubTransportAuthInjectsBearerTokenAsBasicExtraHeader() {
        let encoded = Data("x-access-token:ghp_secret".utf8).base64EncodedString()
        #expect(
            GitTransportAuth.gitHubArguments(token: "ghp_secret") == [
                "-c", "http.https://github.com/.extraheader=Authorization: Basic \(encoded)",
            ]
        )
    }

    @Test
    func gitLabTransportAuthMapsTokenKindsToGitHTTPCredentials() {
        let privateEncoded = Data("oauth2:glpat_secret".utf8).base64EncodedString()
        #expect(
            GitTransportAuth.gitLabArguments(
                host: "gitlab.com", token: .privateToken("glpat_secret")
            ) == [
                "-c", "http.https://gitlab.com/.extraheader=Authorization: Basic \(privateEncoded)",
            ]
        )

        let jobEncoded = Data("gitlab-ci-token:job_secret".utf8).base64EncodedString()
        #expect(
            GitTransportAuth.gitLabArguments(host: "gitlab.com", token: .jobToken("job_secret")) == [
                "-c", "http.https://gitlab.com/.extraheader=Authorization: Basic \(jobEncoded)",
            ]
        )

        #expect(
            GitTransportAuth.gitLabArguments(host: "gitlab.com", token: .bearer("oauth_secret")) == [
                "-c", "http.https://gitlab.com/.extraheader=Authorization: Bearer oauth_secret",
            ]
        )
    }

    @Test
    func gitTransportAuthAddsNoArgumentsForSSHLocations() async {
        let attempts = await withGitConfiguration(.osxkeychain) {
            await GitTransportAuth.attempts(for: "git@github.com:acme/private-lib.git")
        }

        #expect(attempts.map(\.credential) == [.gitConfigured])
        #expect(attempts.map(\.configArguments) == [[]])
    }

    @Test
    func gitTransportAuthTriesGitsOwnCredentialsBeforeAnAmbientToken() async throws {
        // An `http.<base>.extraheader` overrides every credential git would resolve on its
        // own and stops curl reading ~/.netrc, so a token that cannot read the repository
        // used to fail the fetch outright on a machine where plain git succeeds.
        let attempts = await withGitConfiguration(
            .osxkeychain, environment: ["GITHUB_TOKEN": "ghp_secret"]
        ) {
            await GitTransportAuth.attempts(for: "https://github.com/acme/private-lib.git")
        }

        #expect(attempts.map(\.credential) == [.gitConfigured, .gitHubToken])
        #expect(attempts.first?.configArguments == [])
        let encoded = Data("x-access-token:ghp_secret".utf8).base64EncodedString()
        #expect(
            attempts.last?.configArguments == [
                "-c", "http.https://github.com/.extraheader=Authorization: Basic \(encoded)",
            ]
        )
    }

    @Test
    func gitTransportAuthTriesANetrcSourceGitCannotSeeBeforeAnAmbientToken() async throws {
        // `--netrc-file` and SWIFTPM_NETRC_DATA are invisible to git, so they need to be
        // injected, but they are deliberate per-host credentials and outrank a generic token.
        let attempts = await Environment.$netrc.withValue(.invisibleToGit) {
            await withGitConfiguration(.osxkeychain, environment: ["GITHUB_TOKEN": "ghp_secret"]) {
                await GitTransportAuth.attempts(for: "https://github.com/acme/private-lib.git")
            }
        }

        #expect(attempts.map(\.credential) == [.gitConfigured, .netrc, .gitHubToken])
        let encoded = Data("machine-user:s3cret".utf8).base64EncodedString()
        #expect(
            attempts[1].configArguments == [
                "-c", "http.https://github.com/.extraheader=Authorization: Basic \(encoded)",
            ]
        )
    }

    @Test
    func gitTransportAuthAddsNoTokenAttemptWhenNoneIsAvailable() async {
        let attempts = await withGitConfiguration(.empty) {
            await GitTransportAuth.attempts(for: "https://source.example.com/acme/private-lib.git")
        }

        #expect(attempts.map(\.credential) == [.gitConfigured])
    }

    @Test
    func gitTransportAuthTriesAnAmbientTokenFirstWhenGitHasNothingToResolve() async {
        // A CI runner holding only a token has no rewrite rule, no helper and no ~/.netrc,
        // so probing without a credential can only ever cost a round trip.
        let attempts = await withGitConfiguration(
            .empty, environment: ["GITHUB_TOKEN": "ghp_secret"]
        ) {
            await GitTransportAuth.attempts(for: "https://github.com/acme/private-lib.git")
        }

        #expect(attempts.map(\.credential) == [.gitHubToken, .gitConfigured])
    }

    @Test
    func gitTransportAuthStillEndsWithACredentialFreeAttemptWhenGitHasNothingToResolve() async {
        // Dropping it rather than demoting it would break every public dependency the
        // moment the ambient token is expired or scoped elsewhere: an anonymous fetch is
        // what reads them, and an injected Authorization header suppresses it.
        let attempts = await withGitConfiguration(
            .empty, environment: ["GITHUB_TOKEN": "ghp_secret"]
        ) {
            await GitTransportAuth.attempts(for: "https://github.com/acme/public-lib.git")
        }

        #expect(attempts.last?.credential == .gitConfigured)
        #expect(attempts.last?.configArguments == [])
    }

    @Test
    func gitTransportAuthTriesGitFirstWhenTheHostIsCoveredByHomeNetrc() async {
        // ~/.netrc is the one netrc source curl reads for git, so it is a reason to let git
        // go first rather than a reason to inject.
        let attempts = await Environment.$netrc.withValue(.visibleToGit) {
            await withGitConfiguration(.empty, environment: ["GITHUB_TOKEN": "ghp_secret"]) {
                await GitTransportAuth.attempts(for: "https://github.com/acme/private-lib.git")
            }
        }

        #expect(attempts.first?.credential == .gitConfigured)
    }

    @Test
    func gitTransportAuthTriesGitFirstWhenAnAskpassHelperIsConfigured() async {
        // GIT_ASKPASS authenticates without a rewrite, a helper or a netrc, and being an
        // environment variable it never shows up in the config parse.
        let attempts = await withGitConfiguration(
            .empty, environment: ["GITHUB_TOKEN": "ghp_secret", "GIT_ASKPASS": "/usr/bin/true"]
        ) {
            await GitTransportAuth.attempts(for: "https://github.com/acme/private-lib.git")
        }

        #expect(attempts.map(\.credential) == [.gitConfigured, .gitHubToken])
    }

    @Test
    func fetchAttemptsWalkEveryCandidateWithGitsOwnCredentialsFirst() async {
        let attempts = await withGitConfiguration(
            .osxkeychain, environment: ["GITHUB_TOKEN": "ghp_secret"]
        ) {
            await SourceControlLocations.fetchAttempts("git@github.com:acme/private-lib.git")
        }

        #expect(
            attempts.map(\.location) == [
                "git@github.com:acme/private-lib.git",
                "https://github.com/acme/private-lib.git",
                "https://github.com/acme/private-lib.git",
            ]
        )
        #expect(attempts.map(\.credential) == [.gitConfigured, .gitConfigured, .gitHubToken])
    }

    @Test
    func packageIdentityCollapsesTheHTTPSAndSSHFormsOfOneRepository() {
        let identity = SourceControlLocations.packageIdentity("https://github.com/Acme/Private-Lib.git")

        #expect(SourceControlLocations.packageIdentity("git@github.com:Acme/Private-Lib.git") == identity)
        #expect(SourceControlLocations.packageIdentity("https://github.com/Acme/Private-Lib") == identity)
        #expect(SourceControlLocations.packageIdentity("https://github.com/Acme/Other-Lib") != identity)
    }

    @Test
    func canonicalResolvedFileLocationsStabilizeProviderLocations() {
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "https://github.com/CombineCommunity/CombineExt.git"
            )
                == "https://github.com/CombineCommunity/CombineExt"
        )
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "git@github.com:DataDog/dd-sdk-ios.git"
            )
                == "git@github.com:DataDog/dd-sdk-ios"
        )
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "https://gitlab.com/Tuist/SwifterPM.git"
            )
                == "https://gitlab.com/Tuist/SwifterPM"
        )
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "HTTPS://Source.Example.com/Tuist/SwifterPM.git"
            )
                == "https://source.example.com/Tuist/SwifterPM.git"
        )
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "git@Source.Example.com:Tuist/SwifterPM.git"
            )
                == "git@source.example.com:Tuist/SwifterPM.git"
        )
    }

    @Test
    func canonicalResolvedFileLocationsPreserveMixedCaseGitHubOrg() {
        // Git's url.*.insteadOf rules match case-sensitively, so lowercasing
        // the path breaks CI setups that inject credentials per-org. Only the
        // scheme and host are lowercased; the path keeps its declared casing.
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "https://github.com/Fourthline-com/FourthlineSDK-iOS.git"
            )
                == "https://github.com/Fourthline-com/FourthlineSDK-iOS"
        )
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "https://github.com/Fourthline-com/FourthlineSDK-iOS"
            )
                == "https://github.com/Fourthline-com/FourthlineSDK-iOS"
        )
    }
}
