import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class SynthesizedResourceInterfaceProjectMapperTests: TuistUnitTestCase {
    private var subject: SynthesizedResourceInterfaceProjectMapper!
    private var synthesizedResourceInterfacesGenerator: MockNamespaceGenerator!

    override func setUp() {
        super.setUp()

        synthesizedResourceInterfacesGenerator = MockNamespaceGenerator()
        subject = SynthesizedResourceInterfaceProjectMapper(
            synthesizedResourceInterfacesGenerator: synthesizedResourceInterfacesGenerator
        )
    }

    override func tearDown() {
        super.tearDown()

        synthesizedResourceInterfacesGenerator = nil
        subject = nil
    }

    func test_map() throws {
        // Given
        synthesizedResourceInterfacesGenerator.renderStub = { _, _, paths in
            paths
                .map(\.basenameWithoutExt)
                .map { (name: $0, contents: $0) }
        }

        let projectPath = try temporaryPath()
        let targetAPath = projectPath.appending(component: "TargetA")
        let aAssets = targetAPath.appending(component: "a.xcassets")
        let bAssets = targetAPath.appending(component: "b.xcassets")
        let frenchStrings = targetAPath.appending(components: "french", "aStrings.strings")
        let englishStrings = targetAPath.appending(components: "english", "aStrings.strings")

        try fileHandler.createFolder(aAssets)
        try fileHandler.touch(bAssets)
        try fileHandler.touch(frenchStrings)
        try fileHandler.touch(englishStrings)

        let targetA = Target.test(
            name: "TargetA",
            resources: [
                .folderReference(path: aAssets),
                .file(path: bAssets),
                .file(path: frenchStrings),
                .file(path: englishStrings),
            ]
        )

        let project = Project.test(
            path: projectPath,
            targets: [
                targetA,
            ]
        )

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        let derivedPath = projectPath
            .appending(component: Constants.DerivedDirectory.name)
        let derivedSourcesPath = derivedPath
            .appending(component: Constants.DerivedDirectory.sources)
        XCTAssertEqual(
            sideEffects,
            [
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "a.swift"),
                        contents: "a".data(using: .utf8)
                    )
                ),
                .file(
                    FileDescriptor(
                        path: derivedSourcesPath.appending(component: "aStrings.swift"),
                        contents: "aStrings".data(using: .utf8)
                    )
                ),
            ]
        )

        XCTAssertEqual(
            mappedProject,
            Project.test(
                path: projectPath,
                targets: [
                    Target.test(
                        name: targetA.name,
                        sources: [
                            (path: derivedSourcesPath
                                .appending(component: "a.swift"),
                                compilerFlags: nil),
                            (path: derivedSourcesPath
                                .appending(component: "aStrings.swift"),
                                compilerFlags: nil),
                        ],
                        resources: targetA.resources
                    ),
                ]
            )
        )
    }
}
