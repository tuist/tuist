import Foundation
@testable import TuistEnvKit

final class MockGitHubClient: GitHubClienting {
    var releasesStub: (() throws -> [Release])?
    var releaseWithTagStub: ((String) throws -> Release)?
    var getContentStub: ((String, String) throws -> String)?

    func releases() throws -> [Release] {
        try releasesStub?() ?? []
    }

    func release(tag: String) throws -> Release {
        try releaseWithTagStub?(tag) ?? Release.test()
    }

    func getContent(ref: String, path: String) throws -> String {
        try getContentStub?(ref, path) ?? ""
    }
}
