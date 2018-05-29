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

    func test_generateHeadersBuildPhase() throws {
        let buildFile = HeadersBuildFile([AbsolutePath("/test.h")], accessLevel: .public)
        let buildPhase = HeadersBuildPhase(buildFiles: [buildFile])
        let objects = PBXObjects(objects: [:])
        let fileElements = ProjectFileElements()
        let header = PBXFileReference()
        let headerReference = objects.addObject(header)
        fileElements.elements[AbsolutePath("/test.h")] = header
        let target = PBXNativeTarget(name: "Test")
        try subject.generateHeadersBuildPhase(buildPhase,
                                              target: target,
                                              fileElements: fileElements,
                                              objects: objects)
        let pbxBuildPhase: PBXHeadersBuildPhase? = try target.buildPhases.first?.object()
        XCTAssertNotNil(pbxBuildPhase)
        let pbxBuildFile: PBXBuildFile? = try pbxBuildPhase?.files.first?.object()
        XCTAssertNotNil(pbxBuildFile)
        XCTAssertEqual(pbxBuildFile?.settings?["ATTRIBUTES"] as? [String], ["Public"])
        XCTAssertEqual(pbxBuildFile?.fileRef, headerReference)
    }

    func test_generateResourcesBuildPhase_whenLocalizedFile() throws {
        let buildFile = ResourcesBuildFile([AbsolutePath("/en.lproj/Main.storyboard")])
        let buildPhase = ResourcesBuildPhase(buildFiles: [buildFile])
        let fileElements = ProjectFileElements()
        let objects = PBXObjects(objects: [:])
        let group = PBXVariantGroup()
        let groupReference = objects.addObject(group)
        fileElements.elements[AbsolutePath("/Main.storyboard")] = group
        let target = PBXNativeTarget(name: "Test")
        try subject.generateResourcesBuildPhase(buildPhase,
                                                target: target,
                                                fileElements: fileElements,
                                                objects: objects)
        let pbxBuildPhase: PBXResourcesBuildPhase? = try target.buildPhases.first?.object()
        XCTAssertNotNil(pbxBuildPhase)
        let pbxBuildFile: PBXBuildFile? = try pbxBuildPhase?.files.first?.object()
        XCTAssertEqual(pbxBuildFile?.fileRef, groupReference)
    }

    func test_generateResourcesBuildPhase_whenCoreDataModel() throws {
        let buildFile = CoreDataModelBuildFile(AbsolutePath("/Model.xcdatamodeld"),
                                               currentVersion: "1",
                                               versions: [AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")])
        let buildPhase = ResourcesBuildPhase(buildFiles: [buildFile])
        let fileElements = ProjectFileElements()
        let objects = PBXObjects(objects: [:])

        let versionGroup = XCVersionGroup()
        let versionGroupReference = objects.addObject(versionGroup)
        fileElements.elements[AbsolutePath("/Model.xcdatamodeld")] = versionGroup

        let model = PBXFileReference()
        let modelReference = objects.addObject(model)
        versionGroup.children.append(modelReference)
        fileElements.elements[AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")] = model

        let target = PBXNativeTarget(name: "Test")
        try subject.generateResourcesBuildPhase(buildPhase,
                                                target: target,
                                                fileElements: fileElements,
                                                objects: objects)
        let pbxBuildPhase: PBXResourcesBuildPhase? = try target.buildPhases.first?.object()
        XCTAssertNotNil(pbxBuildPhase)
        let pbxBuildFile: PBXBuildFile? = try pbxBuildPhase?.files.first?.object()
        XCTAssertEqual(pbxBuildFile?.fileRef, versionGroupReference)
        XCTAssertEqual(versionGroup.currentVersion, modelReference)
    }

    func test_generateResourcesBuildPhase_whenNormalResource() throws {
        let buildFile = ResourcesBuildFile([AbsolutePath("/image.png")])
        let buildPhase = ResourcesBuildPhase(buildFiles: [buildFile])
        let fileElements = ProjectFileElements()
        let objects = PBXObjects(objects: [:])
        let fileElement = PBXFileReference()
        let fileElementReference = objects.addObject(fileElement)
        fileElements.elements[AbsolutePath("/image.png")] = fileElement
        let target = PBXNativeTarget(name: "Test")
        try subject.generateResourcesBuildPhase(buildPhase,
                                                target: target,
                                                fileElements: fileElements,
                                                objects: objects)
        let pbxBuildPhase: PBXResourcesBuildPhase? = try target.buildPhases.first?.object()
        XCTAssertNotNil(pbxBuildPhase)
        let pbxBuildFile: PBXBuildFile? = try pbxBuildPhase?.files.first?.object()
        XCTAssertEqual(pbxBuildFile?.fileRef, fileElementReference)
    }
}
