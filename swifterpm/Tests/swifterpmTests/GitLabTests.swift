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
    func tokenHeadersMatchGitLabAuthenticationConventions() {
        #expect(GitLabAuth.Token.privateToken("pat").header == ["PRIVATE-TOKEN": "pat"])
        #expect(GitLabAuth.Token.jobToken("job").header == ["JOB-TOKEN": "job"])
        #expect(GitLabAuth.Token.bearer("oauth").header == ["Authorization": "Bearer oauth"])
    }
}
