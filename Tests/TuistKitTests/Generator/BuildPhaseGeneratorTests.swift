import Basic
import Foundation
@testable import xcodeproj
import XCTest
import TuistCoreTesting
@testable import TuistKit

final class BuildPhaseGenerationErrorTests: XCTestCase {
    func test_description_when_missingFileReference() {
        let path = AbsolutePath("/test")
        let expected = "Trying to add a file at path \(path.asString) to a build phase that hasn't been added to the project."
        XCTAssertEqual(BuildPhaseGenerationError.missingFileReference(path).description, expected)
    }

    func test_type_when_missingFileReference() {
        let path = AbsolutePath("/test")
        XCTAssertEqual(BuildPhaseGenerationError.missingFileReference(path).type, .bug)
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
        let target = PBXNativeTarget(name: "Test")
        let objects = PBXObjects()
        objects.addObject(target)
        let fileElements = ProjectFileElements()
        let fileReference = PBXFileReference(sourceTree: .group, name: "Test")
        let fileReferenceReference = objects.addObject(fileReference)
        fileElements.elements[path] = fileReference

        try subject.generateSourcesBuildPhase(files: [path],
                                              pbxTarget: target,
                                              fileElements: fileElements,
                                              objects: objects)

        let buildPhase: PBXSourcesBuildPhase? = try target.buildPhasesReferences.first?.object()
        XCTAssertNotNil(buildPhase)
        let pbxBuildFile: PBXBuildFile? = try buildPhase?.fileReferences.first?.object()
        XCTAssertNotNil(pbxBuildFile)
        XCTAssertEqual(pbxBuildFile?.fileReference, fileReferenceReference)
    }

    func test_generateSourcesBuildPhase_throws_when_theFileReferenceIsMissing() {
        let path = AbsolutePath("/test/file.swift")
        let target = PBXNativeTarget(name: "Test")
        let objects = PBXObjects()
        objects.addObject(target)
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateSourcesBuildPhase(files: [path],
                                                                   pbxTarget: target,
                                                                   fileElements: fileElements,
                                                                   objects: objects)) {
            XCTAssertEqual($0 as? BuildPhaseGenerationError, BuildPhaseGenerationError.missingFileReference(path))
        }
    }

    func test_generateHeadersBuildPhase() throws {
        let path = AbsolutePath("/test.h")
        let headers = Headers.test(public: [path], private: [], project: [])
        let objects = PBXObjects()
        let fileElements = ProjectFileElements()
        let header = PBXFileReference()
        let headerReference = objects.addObject(header)
        fileElements.elements[AbsolutePath("/test.h")] = header
        let target = PBXNativeTarget(name: "Test")

        try subject.generateHeadersBuildPhase(headers: headers,
                                              pbxTarget: target,
                                              fileElements: fileElements,
                                              objects: objects)

        let pbxBuildPhase: PBXHeadersBuildPhase? = try target.buildPhasesReferences.first?.object()
        XCTAssertNotNil(pbxBuildPhase)
        let pbxBuildFile: PBXBuildFile? = try pbxBuildPhase?.fileReferences.first?.object()
        XCTAssertNotNil(pbxBuildFile)
        XCTAssertEqual(pbxBuildFile?.settings?["ATTRIBUTES"] as? [String], ["Public"])
        XCTAssertEqual(pbxBuildFile?.fileReference, headerReference)
    }

    func test_generateResourcesBuildPhase_whenLocalizedFile() throws {
        let path = AbsolutePath("/en.lproj/Main.storyboard")
        let fileElements = ProjectFileElements()
        let objects = PBXObjects()
        let group = PBXVariantGroup()
        let groupReference = objects.addObject(group)
        fileElements.elements[AbsolutePath("/Main.storyboard")] = group
        let target = PBXNativeTarget(name: "Test")

        try subject.generateResourcesBuildPhase(files: [path],
                                                coreDataModels: [],
                                                pbxTarget: target,
                                                fileElements: fileElements,
                                                objects: objects)

        let pbxBuildPhase: PBXResourcesBuildPhase? = try target.buildPhasesReferences.first?.object()
        XCTAssertNotNil(pbxBuildPhase)
        let pbxBuildFile: PBXBuildFile? = try pbxBuildPhase?.fileReferences.first?.object()
        XCTAssertEqual(pbxBuildFile?.fileReference, groupReference)
    }

    func test_generateResourcesBuildPhase_whenCoreDataModel() throws {
        let coreDataModel = CoreDataModel(path: AbsolutePath("/Model.xcdatamodeld"),
                                          versions: [AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")],
                                          currentVersion: "1")
        let fileElements = ProjectFileElements()
        let objects = PBXObjects()

        let versionGroup = XCVersionGroup()
        let versionGroupReference = objects.addObject(versionGroup)
        fileElements.elements[AbsolutePath("/Model.xcdatamodeld")] = versionGroup

        let model = PBXFileReference()
        let modelReference = objects.addObject(model)
        versionGroup.childrenReferences.append(modelReference)
        fileElements.elements[AbsolutePath("/Model.xcdatamodeld/1.xcdatamodel")] = model

        let target = PBXNativeTarget(name: "Test")
        try subject.generateResourcesBuildPhase(files: [],
                                                coreDataModels: [coreDataModel],
                                                pbxTarget: target,
                                                fileElements: fileElements,
                                                objects: objects)

        let pbxBuildPhase: PBXResourcesBuildPhase? = try target.buildPhasesReferences.first?.object()
        XCTAssertNotNil(pbxBuildPhase)
        let pbxBuildFile: PBXBuildFile? = try pbxBuildPhase?.fileReferences.first?.object()
        XCTAssertEqual(pbxBuildFile?.fileReference, versionGroupReference)
        XCTAssertEqual(versionGroup.currentVersion, modelReference)
    }

    func test_generateResourcesBuildPhase_whenNormalResource() throws {
        let path = AbsolutePath("/image.png")
        let fileElements = ProjectFileElements()
        let objects = PBXObjects()
        let fileElement = PBXFileReference()
        let fileElementReference = objects.addObject(fileElement)
        fileElements.elements[path] = fileElement
        let target = PBXNativeTarget(name: "Test")

        try subject.generateResourcesBuildPhase(files: [path],
                                                coreDataModels: [],
                                                pbxTarget: target,
                                                fileElements: fileElements,
                                                objects: objects)

        let pbxBuildPhase: PBXResourcesBuildPhase? = try target.buildPhasesReferences.first?.object()
        XCTAssertNotNil(pbxBuildPhase)
        let pbxBuildFile: PBXBuildFile? = try pbxBuildPhase?.fileReferences.first?.object()
        XCTAssertEqual(pbxBuildFile?.fileReference, fileElementReference)
    }
}
