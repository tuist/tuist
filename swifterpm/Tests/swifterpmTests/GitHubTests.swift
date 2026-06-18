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
    func sourceControlFetchLocationsPreferOriginalThenProviderSSH() {
        #expect(
            SourceControlLocations.fetchCandidates("https://github.com/tuist/swifterpm") == [
                "https://github.com/tuist/swifterpm",
                "git@github.com:tuist/swifterpm.git",
            ])
        #expect(
            SourceControlLocations.fetchCandidates("git@github.com:tuist/swifterpm.git") == [
                "git@github.com:tuist/swifterpm.git"
            ])
        #expect(
            SourceControlLocations.fetchCandidates("https://gitlab.com/tuist/swifterpm") == [
                "https://gitlab.com/tuist/swifterpm",
                "git@gitlab.com:tuist/swifterpm.git",
            ])
    }
}
