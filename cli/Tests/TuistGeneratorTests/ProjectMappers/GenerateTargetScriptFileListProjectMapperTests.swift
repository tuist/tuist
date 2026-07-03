import Path
import TuistCore
import XcodeGraph
import XCTest
@testable import TuistGenerator
@testable import TuistTesting

final class GenerateTargetScriptFileListProjectMapperTests: TuistUnitTestCase {
    func test_map_returns_sideEffectsToCreateGeneratedFileLists() throws {
        // Given
        let subject = GenerateTargetScriptFileListProjectMapper()
        let fileListPath = try AbsolutePath(validating: "/Project/SourceryInputs.xcfilelist")
        let nestedFileListPath = try AbsolutePath(validating: "/Project/Generated/Outputs.xcfilelist")
        let scriptA = TargetScript(
            name: "Script A",
            order: .pre,
            inputFileListPaths: [
                .init(path: "SourceryInputs.xcfilelist", generatedPlaceholderPath: fileListPath),
            ],
            outputFileListPaths: [
                .init(path: "Generated/Outputs.xcfilelist", generatedPlaceholderPath: nestedFileListPath),
            ]
        )
        let scriptB = TargetScript(
            name: "Script B",
            order: .post,
            inputFileListPaths: [
                .init(path: "SourceryInputs.xcfilelist", generatedPlaceholderPath: fileListPath),
            ]
        )
        let target = Target.test(name: "A", scripts: [scriptA, scriptB])
        let project = Project.test(targets: [target])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(mappedProject, project)
        XCTAssertEqual(
            sideEffects,
            [
                .file(FileDescriptor(path: fileListPath)),
                .file(FileDescriptor(path: nestedFileListPath)),
            ]
        )
    }
}
