import Testing
import XcodeGraph
@testable import TuistCore

struct ProjectExternalHashTests {
    @Test func externalHash_isTheResolutionHashOfAPackage_andNilForTheRepositoryProjects() {
        #expect(Project.test(type: .local).externalHash == nil)
        #expect(Project.test(type: .external(hash: nil)).externalHash == nil)
        #expect(Project.test(type: .external(hash: "revision")).externalHash == "revision")
        #expect(Project.test(type: .external(hash: "")).externalHash == "")
    }
}
