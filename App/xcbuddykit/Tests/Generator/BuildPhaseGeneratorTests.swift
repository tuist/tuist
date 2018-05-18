import Basic
import Foundation
@testable import xcbuddykit
@testable import xcodeproj
import XCTest

final class BuildPhaseGeneratorTests: XCTestCase {
    var subject: BuildPhaseGenerator!
    var errorHandler: MockErrorHandler!
    var context: GeneratorContext!

    override func setUp() {
        subject = BuildPhaseGenerator()
        errorHandler = MockErrorHandler()
        context = GeneratorContext(graph: Graph.test(), errorHandler: errorHandler)
    }

    func test_generateSourcesBuildPhase() throws {
        let path = AbsolutePath("/test/file.swift")
        let buildFiles = BuildFiles(files: Set([path]))
        let buildPhaseSpec = SourcesBuildPhase(buildFiles: buildFiles)
        let target = PBXNativeTarget(name: "Test")
        let objects = PBXObjects(objects: [:])
        objects.addObject(target)
        let fileElements = ProjectFileElements()
        let fileReference = PBXFileReference(sourceTree: .group, name: "Test")
        let fileReferenceReference = objects.addObject(fileReference)
        fileElements.elements[path] = fileReference
        subject.generateSourcesBuildPhase(buildPhaseSpec,
                                          target: target,
                                          fileElements: fileElements,
                                          objects: objects,
                                          context: context)
        let buildPhase: PBXSourcesBuildPhase? = try target.buildPhases.first?.object()
        XCTAssertNotNil(buildPhase)
        let buildFile: PBXBuildFile? = try buildPhase?.files.first?.object()
        XCTAssertNotNil(buildFile)
        XCTAssertEqual(buildFile?.fileRef, fileReferenceReference)
    }

    func test_generateSourcesBuildPhase_fatals_when_theFileReferenceIsMissing() {
        let path = AbsolutePath("/test/file.swift")
        let buildFiles = BuildFiles(files: Set([path]))
        let buildPhase = SourcesBuildPhase(buildFiles: buildFiles)
        let target = PBXNativeTarget(name: "Test")
        let objects = PBXObjects(objects: [:])
        objects.addObject(target)
        let fileElements = ProjectFileElements()
        subject.generateSourcesBuildPhase(buildPhase,
                                          target: target,
                                          fileElements: fileElements,
                                          objects: objects,
                                          context: context)
        let error = errorHandler.fatalErrorArgs.first
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.isSilent == true)
        XCTAssertTrue(error?.isBug == true)
        let expected = BuildPhaseGenerationError.missingFileReference(path)
        XCTAssertEqual(error?.bug as? BuildPhaseGenerationError, expected)
    }
}
