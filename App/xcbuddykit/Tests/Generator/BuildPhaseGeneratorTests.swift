import Basic
import Foundation
@testable import xcbuddykit
@testable import xcodeproj
import XCTest

final class BuildPhaseGenerationErrorTests: XCTestCase {
    func test_description_when_missingFileReference() {
        let path = AbsolutePath("/test")
        let expected = "Trying to add a file at path \(path) to a build phase that hasn't been added to the project."
        XCTAssertEqual(BuildPhaseGenerationError.missingFileReference(path).description, expected)
    }

    func test_type_when_missingFileReference() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(BuildPhaseGenerationError.missingFileReference(path).type, .bugSilent)
    }
}

final class BuildPhaseGeneratorTests: XCTestCase {
    var subject: BuildPhaseGenerator!
    var errorHandler: MockErrorHandler!
    var context: GeneratorContext!

    override func setUp() {
        subject = BuildPhaseGenerator()
        errorHandler = MockErrorHandler()
        context = GeneratorContext(graph: Graph.test())
    }

    func test_generateSourcesBuildPhase() throws {
        let path = AbsolutePath("/test/file.swift")
        let buildFile = SourcesBuildFile([path])
        let buildPhaseSpec = SourcesBuildPhase(buildFiles: [buildFile])
        let target = PBXNativeTarget(name: "Test")
        let objects = PBXObjects(objects: [:])
        objects.addObject(target)
        let fileElements = ProjectFileElements()
        let fileReference = PBXFileReference(sourceTree: .group, name: "Test")
        let fileReferenceReference = objects.addObject(fileReference)
        fileElements.elements[path] = fileReference
        try subject.generateSourcesBuildPhase(buildPhaseSpec,
                                              target: target,
                                              fileElements: fileElements,
                                              objects: objects)
        let buildPhase: PBXSourcesBuildPhase? = try target.buildPhases.first?.object()
        XCTAssertNotNil(buildPhase)
        let pbxBuildFile: PBXBuildFile? = try buildPhase?.files.first?.object()
        XCTAssertNotNil(pbxBuildFile)
        XCTAssertEqual(pbxBuildFile?.fileRef, fileReferenceReference)
    }

    func test_generateSourcesBuildPhase_fatals_when_theFileReferenceIsMissing() {
        let path = AbsolutePath("/test/file.swift")
        let buildFile = SourcesBuildFile([path])
        let buildPhase = SourcesBuildPhase(buildFiles: [buildFile])
        let target = PBXNativeTarget(name: "Test")
        let objects = PBXObjects(objects: [:])
        objects.addObject(target)
        let fileElements = ProjectFileElements()
        XCTAssertThrowsError(try subject.generateSourcesBuildPhase(buildPhase,
                                                                   target: target,
                                                                   fileElements: fileElements,
                                                                   objects: objects)) {
            XCTAssertEqual($0 as? BuildPhaseGenerationError, BuildPhaseGenerationError.missingFileReference(path))
        }
    }
}
