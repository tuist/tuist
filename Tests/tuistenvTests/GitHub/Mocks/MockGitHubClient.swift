import Foundation
@testable import tuistenv

final class MockGitHubClient: GitHubClienting {
    var releasesStub: (() throws -> [Release])?
    var releaseWithTagStub: ((String) throws -> Release)?
    var getContentStub: ((String, String) throws -> String)?

    func releases() throws -> [Release] {
        return try releasesStub?() ?? []
    }

    func release(tag: String) throws -> Release {
        return try releaseWithTagStub?(tag) ?? Release.test()
    }

    func getContent(ref: String, path: String) throws -> String {
        return try getContentStub?(ref, path) ?? ""
    }
}
