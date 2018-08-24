import Foundation
@testable import TuistEnvKit

final class MockGitHubClient: GitHubClienting {
    var releasesStub: (() throws -> [Release])?
    var releaseStub: ((String) throws -> Release)?

    func releases() throws -> [Release] {
        return try releasesStub?() ?? []
    }

    func release(tag: String) throws -> Release {
        return try releaseStub?(tag) ?? Release.test()
    }
}
