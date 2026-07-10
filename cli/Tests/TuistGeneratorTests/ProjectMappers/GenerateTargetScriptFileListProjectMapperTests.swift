import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistGenerator

struct GenerateTargetScriptFileListProjectMapperTests {
    @Test
    func map_returns_sideEffectsToCreateGeneratedFileLists() throws {
        // Given
        let subject = GenerateTargetScriptFileListProjectMapper()
        let fileListPath = try AbsolutePath(validating: "/Project/SourceryInputs.xcfilelist")
        let nestedFileListPath = try AbsolutePath(validating: "/Project/Generated/Outputs.xcfilelist")
        let scriptA = TargetScript(
            name: "Script A",
            order: .pre,
            inputFileListPaths: [
                .generated(fileListPath),
            ],
            outputFileListPaths: [
                .generated(nestedFileListPath),
            ]
        )
        let scriptB = TargetScript(
            name: "Script B",
            order: .post,
            inputFileListPaths: [
                .generated(fileListPath),
            ]
        )
        let target = Target.test(name: "A", scripts: [scriptA, scriptB])
        let project = Project.test(targets: [target])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        #expect(mappedProject == project)
        #expect(
            sideEffects == [
                .file(FileDescriptor(path: fileListPath)),
                .file(FileDescriptor(path: nestedFileListPath)),
            ]
        )
    }
}
