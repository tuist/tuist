import Basic
import Foundation
@testable import TuistKit
@testable import xcodeproj
import XCTest

final class LinkGeneratorErrorTests: XCTestCase {
    var subject: LinkGenerator!

    override func setUp() {
        super.setUp()
        subject = LinkGenerator()
    }

    func test_linkGeneratorError_description() {
        XCTAssertEqual(LinkGeneratorError.missingProduct(name: "name").description, "Couldn't find a reference for the product name.")
        XCTAssertEqual(LinkGeneratorError.missingReference(path: AbsolutePath("/")).description, "Couldn't find a reference for the file at path /.")
        XCTAssertEqual(LinkGeneratorError.missingConfigurationList(targetName: "target").description, "The target target doesn't have a configuration list.")
    }

    func test_linkGeneratorError_type() {
        XCTAssertEqual(LinkGeneratorError.missingProduct(name: "name").type, .bug)
        XCTAssertEqual(LinkGeneratorError.missingReference(path: AbsolutePath("/")).type, .bug)
        XCTAssertEqual(LinkGeneratorError.missingConfigurationList(targetName: "target").type, .bug)
    }

    func test_generateEmbedPhase() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.absolute(AbsolutePath("/test.framework")))
        dependencies.append(DependencyReference.product("waka.framework"))
        let objects = PBXObjects()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let wakaFile = PBXFileReference()
        let wakaFileReference = objects.addObject(wakaFile)
        fileElements.products["waka.framework"] = wakaFile
        let resourceLocator = MockResourceLocator()
        resourceLocator.embedPathStub = { AbsolutePath("/embed") }
        let sourceRootPath = AbsolutePath("/")

        try subject.generateEmbedPhase(dependencies: dependencies,
                                       pbxTarget: pbxTarget,
                                       objects: objects,
                                       fileElements: fileElements,
                                       resourceLocator: resourceLocator,
                                       sourceRootPath: sourceRootPath)

        let scriptBuildPhase: PBXShellScriptBuildPhase? = try pbxTarget.buildPhasesReferences.first?.object()
        XCTAssertEqual(scriptBuildPhase?.name, "Embed Precompiled Frameworks")
        XCTAssertEqual(scriptBuildPhase?.shellScript, "/ embed test.framework")
        XCTAssertEqual(scriptBuildPhase?.inputPaths, ["$(SRCROOT)/test.framework"])
        XCTAssertEqual(scriptBuildPhase?.outputPaths, ["$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/test.framework"])

        let copyBuildPhase: PBXCopyFilesBuildPhase? = try pbxTarget.buildPhasesReferences.last?.object()
        XCTAssertEqual(copyBuildPhase?.name, "Embed Frameworks")
        let wakaBuildFile: PBXBuildFile? = try copyBuildPhase?.fileReferences.first?.object()
        XCTAssertEqual(wakaBuildFile?.fileReference, wakaFileReference)
    }

    func test_generateEmbedPhase_throws_when_aProductIsMissing() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.product("waka.framework"))
        let objects = PBXObjects()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let resourceLocator = MockResourceLocator()
        resourceLocator.embedPathStub = { AbsolutePath("/embed") }
        let sourceRootPath = AbsolutePath("/")

        XCTAssertThrowsError(try subject.generateEmbedPhase(dependencies: dependencies,
                                                            pbxTarget: pbxTarget,
                                                            objects: objects,
                                                            fileElements: fileElements,
                                                            resourceLocator: resourceLocator,
                                                            sourceRootPath: sourceRootPath)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingProduct(name: "waka.framework"))
        }
    }

    func test_setupFrameworkSearchPath() throws {
        let dependencies = [
            DependencyReference.absolute(AbsolutePath("/Dependencies/A.framework")),
            DependencyReference.absolute(AbsolutePath("/Dependencies/B.framework")),
            DependencyReference.absolute(AbsolutePath("/Dependencies/C/C.framework")),
        ]
        let sourceRootPath = AbsolutePath("/")

        let objects = PBXObjects()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let configurationList = XCConfigurationList(buildConfigurationsReferences: [])
        pbxTarget.buildConfigurationListReference = objects.addObject(configurationList)
        let debugConfig = XCBuildConfiguration(name: "Debug")
        let releaseConfig = XCBuildConfiguration(name: "Release")
        configurationList.buildConfigurationsReferences.append(objects.addObject(debugConfig))
        configurationList.buildConfigurationsReferences.append(objects.addObject(releaseConfig))

        try subject.setupFrameworkSearchPath(dependencies: dependencies,
                                             pbxTarget: pbxTarget,
                                             sourceRootPath: sourceRootPath)

        let expected = "$(SRCROOT)/Dependencies $(SRCROOT)/Dependencies/C"
        XCTAssertEqual(debugConfig.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? String, expected)
        XCTAssertEqual(releaseConfig.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? String, expected)
    }

    func test_setupHeadersSearchPath() throws {
        let headersFolders = [AbsolutePath("/headers")]
        let objects = PBXObjects()

        let pbxTarget = PBXNativeTarget(name: "Test")
        objects.addObject(pbxTarget)

        let configurationList = XCConfigurationList(buildConfigurationsReferences: [])
        let configurationListReference = objects.addObject(configurationList)
        pbxTarget.buildConfigurationListReference = configurationListReference

        let config = XCBuildConfiguration(name: "Debug")
        let configReference = objects.addObject(config)
        configurationList.buildConfigurationsReferences.append(configReference)

        let sourceRootPath = AbsolutePath("/")

        try subject.setupHeadersSearchPath(headersFolders,
                                           pbxTarget: pbxTarget,
                                           sourceRootPath: sourceRootPath)

        XCTAssertEqual(config.buildSettings["HEADER_SEARCH_PATHS"] as? String, " $(SRCROOT)/headers")
    }

    func test_setupHeadersSearchPath_throws_whenTheConfigurationListIsMissing() throws {
        let headersFolders = [AbsolutePath("/headers")]
        let objects = PBXObjects()

        let pbxTarget = PBXNativeTarget(name: "Test")
        objects.addObject(pbxTarget)
        let sourceRootPath = AbsolutePath("/")

        XCTAssertThrowsError(try subject.setupHeadersSearchPath(headersFolders,
                                                                pbxTarget: pbxTarget,
                                                                sourceRootPath: sourceRootPath)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingConfigurationList(targetName: pbxTarget.name))
        }
    }

    func test_generateLinkingPhase() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.absolute(AbsolutePath("/test.framework")))
        dependencies.append(DependencyReference.product("waka.framework"))
        let objects = PBXObjects()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let testFile = PBXFileReference()
        let testFileReference = objects.addObject(testFile)
        let wakaFile = PBXFileReference()
        let wakaFileReference = objects.addObject(wakaFile)
        fileElements.products["waka.framework"] = wakaFile
        fileElements.elements[AbsolutePath("/test.framework")] = testFile

        try subject.generateLinkingPhase(dependencies: dependencies,
                                         pbxTarget: pbxTarget,
                                         objects: objects,
                                         fileElements: fileElements)

        let buildPhase: PBXFrameworksBuildPhase? = try pbxTarget.buildPhasesReferences.last?.object()

        let testBuildFile: PBXBuildFile? = try buildPhase?.fileReferences.first?.object()
        let wakaBuildFile: PBXBuildFile? = try buildPhase?.fileReferences.last?.object()

        XCTAssertEqual(testBuildFile?.fileReference, testFileReference)
        XCTAssertEqual(wakaBuildFile?.fileReference, wakaFileReference)
    }

    func test_generateLinkingPhase_throws_whenFileReferenceIsMissing() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.absolute(AbsolutePath("/test.framework")))
        let objects = PBXObjects()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateLinkingPhase(dependencies: dependencies,
                                                              pbxTarget: pbxTarget,
                                                              objects: objects,
                                                              fileElements: fileElements)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingReference(path: AbsolutePath("/test.framework")))
        }
    }

    func test_generateLinkingPhase_throws_whenProductIsMissing() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.product("waka.framework"))
        let objects = PBXObjects()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateLinkingPhase(dependencies: dependencies,
                                                              pbxTarget: pbxTarget,
                                                              objects: objects,
                                                              fileElements: fileElements)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingProduct(name: "waka.framework"))
        }
    }
}
