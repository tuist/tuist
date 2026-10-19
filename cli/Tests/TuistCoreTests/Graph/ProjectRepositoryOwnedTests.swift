import Testing
import XcodeGraph
@testable import TuistCore

struct ProjectRepositoryOwnedTests {
    @Test func isRepositoryOwned_forTheWorkspaceProjectsAndPackagesReferencedByPath() {
        #expect(Project.test(type: .local).isRepositoryOwned)
        #expect(Project.test(type: .external(hash: nil)).isRepositoryOwned)
        #expect(!Project.test(type: .external(hash: "revision")).isRepositoryOwned)
        #expect(!Project.test(type: .external(hash: "")).isRepositoryOwned)
    }
}
