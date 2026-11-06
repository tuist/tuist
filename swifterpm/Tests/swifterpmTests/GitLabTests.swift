import Foundation
import Testing
@testable import SwifterPMCore

struct GitLabTests {
    @Test
    func parsesHTTPSGitLabLocations() throws {
        let repo = try GitLabRepo(location: "https://gitlab.com/tuist/swifterpm.git")

        #expect(repo.scheme == "https")
        #expect(repo.host == "gitlab.com")
        #expect(repo.pathWithNamespace == "tuist/swifterpm")
        #expect(repo.encodedProjectPath == "tuist%2Fswifterpm")
    }

    @Test
    func parsesSSHGitLabLocations() throws {
        let repo = try GitLabRepo(location: "git@gitlab.com:tuist/swifterpm.git")

        #expect(repo.scheme == "https")
        #expect(repo.host == "gitlab.com")
        #expect(repo.pathWithNamespace == "tuist/swifterpm")
    }

    @Test
    func rejectsNonGitLabLocations() {
        #expect(throws: (any Error).self) {
            try GitLabRepo(location: "https://github.com/tuist/swifterpm")
        }
    }

    @Test
    func gitlabAPIRequiresAnExplicitProviderToken() async throws {
        let url = try #require(URL(string: "https://gitlab.com/api/v4"))
        await Environment.$values.withValue([
            "GITLAB_TOKEN": "ambient", "GITLAB_ACCESS_TOKEN": "ambient",
            "OAUTH_TOKEN": "ambient", "CI_JOB_TOKEN": "ambient",
        ]) {
            #expect(await GitLabAuth.token(for: url) == nil)
        }
        await Environment.$values.withValue(["SWIFTERPM_GITLAB_TOKEN": " explicit "]) {
            #expect(await GitLabAuth.token(for: url)?.header == ["PRIVATE-TOKEN": "explicit"])
        }
        await Environment.$values.withValue([:]) {
            #expect(await GitLabAuth.token(for: url) == nil)
        }
    }

    @Test(arguments: [
        "https://gitlab.evil.example/project/package", "http://gitlab.com/project/package",
    ])
    func gitlabTokenIsNotSentToUntrustedOrInsecureAPIs(location: String) async throws {
        try await Environment.$values.withValue(["SWIFTERPM_GITLAB_TOKEN": "explicit"]) {
            let repo = try GitLabRepo(location: location)
            #expect(await GitLabAuth.token(for: repo.apiBaseURL) == nil)
            #expect(await GitLabAuth.hasSession(for: repo) == false)
        }
    }

    @Test(arguments: ["SWIFTERPM_GITLAB_HOST", "GITLAB_HOST", "GITLAB_URI", "CI_SERVER_HOST", "CI_SERVER_FQDN"])
    func gitlabTokenAllowsExplicitlyConfiguredHTTPSHosts(key: String) async throws {
        try await Environment.$values.withValue([
            "SWIFTERPM_GITLAB_TOKEN": "explicit", key: "https://source.example.com:8443",
        ]) {
            let repo = try GitLabRepo(location: "https://source.example.com/project/package")
            #expect(await GitLabAuth.token(for: repo.apiBaseURL)?.header == ["PRIVATE-TOKEN": "explicit"])
        }
    }

    @Test(arguments: ["https://gitlab.com", "http://gitlab.com"])
    func gitlabTokenChecksTheFinalAPIScheme(apiHost: String) async throws {
        try await Environment.$values.withValue([
            "SWIFTERPM_GITLAB_TOKEN": "explicit", "GITLAB_URI": apiHost,
        ]) {
            let repo = try GitLabRepo(location: "https://gitlab.com/project/package")
            // GITLAB_URI controls the scheme, not the API host; HTTP must disable API auth.
            let token = await GitLabAuth.token(for: repo.apiBaseURL)
            #expect(token?.header == (apiHost.hasPrefix("https") ? ["PRIVATE-TOKEN": "explicit"] : nil))
        }
    }

    @Test
    func tokenHeadersMatchGitLabAuthenticationConventions() {
        #expect(GitLabAuth.Token.privateToken("pat").header == ["PRIVATE-TOKEN": "pat"])
        #expect(GitLabAuth.Token.jobToken("job").header == ["JOB-TOKEN": "job"])
        #expect(GitLabAuth.Token.bearer("oauth").header == ["Authorization": "Bearer oauth"])
    }
}
