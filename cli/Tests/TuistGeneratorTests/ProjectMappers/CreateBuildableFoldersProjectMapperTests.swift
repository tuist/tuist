import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistGenerator

struct CreateBuildableFoldersProjectMapperTests {
    private let subject = CreateBuildableFoldersProjectMapper()

    @Test
    func map_createsFoldersThatDeclareContents() throws {
        // Given
        let declared = try AbsolutePath(validating: "/Project/Generated")
        let scanned = try AbsolutePath(validating: "/Project/Sources")
        let project = Project.test(targets: [
            Target.test(name: "A", buildableFolders: [
                BuildableFolder(path: scanned, exceptions: [], resolvedFiles: []),
                BuildableFolder(path: declared, exceptions: [], resolvedFiles: [], contents: [.sources]),
            ]),
            Target.test(name: "B", buildableFolders: [
                BuildableFolder(path: declared, exceptions: [], resolvedFiles: [], contents: [.resources]),
            ]),
        ])

        // When
        let (gotProject, gotSideEffects) = try subject.map(project: project)

        // Then
        #expect(gotProject == project)
        #expect(gotSideEffects == [.directory(DirectoryDescriptor(path: declared, state: .present))])
    }

    @Test
    func map_withoutDeclaredFolders_hasNoSideEffects() throws {
        // Given
        let project = Project.test(targets: [
            Target.test(buildableFolders: [
                BuildableFolder(path: try AbsolutePath(validating: "/Project/Sources"), exceptions: [], resolvedFiles: []),
            ]),
        ])

        // When
        let (_, gotSideEffects) = try subject.map(project: project)

        // Then
        #expect(gotSideEffects.isEmpty)
    }
}
