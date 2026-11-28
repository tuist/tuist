import Testing
import TuistGenerator
@testable import TuistKit

struct CreateBuildableFoldersProjectMapperOrderingTests {
    @Test func createsDeclaredFoldersAfterDeletingDerived() throws {
        let mappers = ProjectMapperFactory().default(tuist: .default)
        let deleteDerived = try #require(mappers.firstIndex { $0 is DeleteDerivedDirectoryProjectMapper })
        let createFolders = try #require(mappers.firstIndex { $0 is CreateBuildableFoldersProjectMapper })

        #expect(deleteDerived < createFolders)
    }
}
