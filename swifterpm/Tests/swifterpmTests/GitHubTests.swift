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

    @Test(arguments: [
        "HTTPS://GitHub.com/tuist/swifterpm.git",
        "git@GitHub.com:tuist/swifterpm.git",
    ])
    func parsesGitHubLocationsWithMixedCaseHosts(location: String) throws {
        let repo = try GitHubRepo(location: location)

        #expect(repo.owner == "tuist")
        #expect(repo.repo == "swifterpm")
    }

    @Test
    func rejectsNonGitHubLocations() {
        #expect(throws: (any Error).self) {
            try GitHubRepo(location: "https://gitlab.com/tuist/swifterpm")
        }
    }

    @Test(arguments: [
        "https://github.com/tuist/swifterpm", "git@github.com:acme/private-lib",
        "https://gitlab.com/tuist/swifterpm", "git@gitlab.com:acme/private-lib.git",
        "https://mirror.example.com/swifterpm.git",
    ])
    func sourceControlFetchPreservesTheDeclaredTransport(location: String) {
        #expect(SourceControlLocations.fetchCandidates(location) == [location])
    }

    @Test
    func githubAPIRequiresAnExplicitProviderToken() async {
        #expect(GitHubAuth.envToken(from: ["GITHUB_TOKEN": "ambient", "GH_TOKEN": "ambient"]) == nil)
        #expect(GitHubAuth.envToken(from: ["SWIFTERPM_GITHUB_TOKEN": " ", "GITHUB_TOKEN": "ambient"]) == nil)
        #expect(GitHubAuth.envToken(from: ["SWIFTERPM_GITHUB_TOKEN": " explicit "]) == "explicit")
        await Environment.$values.withValue(["SWIFTERPM_GITHUB_TOKEN": "scoped-token"]) {
            #expect(await GitHubAuth.token() == "scoped-token")
        }
        await Environment.$values.withValue([:]) {
            #expect(await GitHubAuth.token() == nil)
        }
    }

    @Test
    func canonicalLocationsStabilizeProviderLocations() {
        #expect(
            SourceControlLocations.canonicalLocation(
                "https://github.com/CombineCommunity/CombineExt.git"
            )
                == "https://github.com/CombineCommunity/CombineExt"
        )
        #expect(
            SourceControlLocations.canonicalLocation(
                "git@github.com:DataDog/dd-sdk-ios.git"
            )
                == "git@github.com:DataDog/dd-sdk-ios"
        )
        #expect(
            SourceControlLocations.canonicalLocation(
                "https://gitlab.com/Tuist/SwifterPM.git"
            )
                == "https://gitlab.com/Tuist/SwifterPM"
        )
        #expect(
            SourceControlLocations.canonicalLocation(
                "HTTPS://Source.Example.com/Tuist/SwifterPM.git"
            )
                == "https://source.example.com/Tuist/SwifterPM.git"
        )
        #expect(
            SourceControlLocations.canonicalLocation(
                "git@Source.Example.com:Tuist/SwifterPM.git"
            )
                == "git@source.example.com:Tuist/SwifterPM.git"
        )
    }

    @Test
    func canonicalLocationsPreserveMixedCaseGitHubOrg() {
        // Git's url.*.insteadOf rules match case-sensitively, so lowercasing
        // the path breaks CI setups that inject credentials per-org. Only the
        // scheme and host are lowercased; the path keeps its declared casing.
        #expect(
            SourceControlLocations.canonicalLocation(
                "https://github.com/Fourthline-com/FourthlineSDK-iOS.git"
            )
                == "https://github.com/Fourthline-com/FourthlineSDK-iOS"
        )
        #expect(
            SourceControlLocations.canonicalLocation(
                "https://github.com/Fourthline-com/FourthlineSDK-iOS"
            )
                == "https://github.com/Fourthline-com/FourthlineSDK-iOS"
        )
    }
}
