import Foundation
import Testing
@testable import SwifterPMCore

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
        #expect(await GitTransportAuth.configArguments(for: "git@github.com:acme/private-lib.git") == [])
    }

    @Test
    func canonicalResolvedFileLocationsStabilizeProviderLocations() {
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "https://github.com/CombineCommunity/CombineExt.git"
            )
                == "https://github.com/combinecommunity/combineext"
        )
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "git@github.com:DataDog/dd-sdk-ios.git"
            )
                == "git@github.com:datadog/dd-sdk-ios"
        )
        #expect(
            SourceControlLocations.canonicalResolvedFileLocation(
                "https://gitlab.com/Tuist/SwifterPM.git"
            )
                == "https://gitlab.com/tuist/swifterpm"
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
}
