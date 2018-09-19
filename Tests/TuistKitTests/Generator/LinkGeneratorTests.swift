import Basic
import Foundation
@testable import TuistKit
import xcodeproj
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
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let wakaFile = PBXFileReference()
        pbxproj.add(object: wakaFile)
        fileElements.products["waka.framework"] = wakaFile
        let resourceLocator = MockResourceLocator()
        resourceLocator.embedPathStub = { AbsolutePath("/embed") }
        let sourceRootPath = AbsolutePath("/")

        try subject.generateEmbedPhase(dependencies: dependencies,
                                       pbxTarget: pbxTarget,
                                       pbxproj: pbxproj,
                                       fileElements: fileElements,
                                       resourceLocator: resourceLocator,
                                       sourceRootPath: sourceRootPath)

        let scriptBuildPhase: PBXShellScriptBuildPhase? = pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase
        XCTAssertEqual(scriptBuildPhase?.name, "Embed Precompiled Frameworks")
        XCTAssertEqual(scriptBuildPhase?.shellScript, "/ embed test.framework")
        XCTAssertEqual(scriptBuildPhase?.inputPaths, ["$(SRCROOT)/test.framework"])
        XCTAssertEqual(scriptBuildPhase?.outputPaths, ["$(BUILT_PRODUCTS_DIR)/$(FRAMEWORKS_FOLDER_PATH)/test.framework"])

        let copyBuildPhase: PBXCopyFilesBuildPhase? = pbxTarget.buildPhases.last as? PBXCopyFilesBuildPhase
        XCTAssertEqual(copyBuildPhase?.name, "Embed Frameworks")
        let wakaBuildFile: PBXBuildFile? = copyBuildPhase?.files.first
        XCTAssertEqual(wakaBuildFile?.file, wakaFile)
    }

    func test_generateEmbedPhase_throws_when_aProductIsMissing() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.product("waka.framework"))
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let resourceLocator = MockResourceLocator()
        resourceLocator.embedPathStub = { AbsolutePath("/embed") }
        let sourceRootPath = AbsolutePath("/")

        XCTAssertThrowsError(try subject.generateEmbedPhase(dependencies: dependencies,
                                                            pbxTarget: pbxTarget,
                                                            pbxproj: pbxproj,
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

        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)
        pbxTarget.buildConfigurationList = configurationList

        let debugConfig = XCBuildConfiguration(name: "Debug")
        let releaseConfig = XCBuildConfiguration(name: "Release")
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)
        configurationList.buildConfigurations.append(debugConfig)
        configurationList.buildConfigurations.append(releaseConfig)

        try subject.setupFrameworkSearchPath(dependencies: dependencies,
                                             pbxTarget: pbxTarget,
                                             sourceRootPath: sourceRootPath)

        let expected = "$(SRCROOT)/Dependencies $(SRCROOT)/Dependencies/C"
        XCTAssertEqual(debugConfig.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? String, expected)
        XCTAssertEqual(releaseConfig.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? String, expected)
    }

    func test_setupHeadersSearchPath() throws {
        let headersFolders = [AbsolutePath("/headers")]
        let pbxproj = PBXProj()

        let pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)

        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)
        pbxTarget.buildConfigurationList = configurationList

        let config = XCBuildConfiguration(name: "Debug")
        pbxproj.add(object: config)
        configurationList.buildConfigurations.append(config)

        let sourceRootPath = AbsolutePath("/")

        try subject.setupHeadersSearchPath(headersFolders,
                                           pbxTarget: pbxTarget,
                                           sourceRootPath: sourceRootPath)

        XCTAssertEqual(config.buildSettings["HEADER_SEARCH_PATHS"] as? String, " $(SRCROOT)/headers")
    }

    func test_setupHeadersSearchPath_throws_whenTheConfigurationListIsMissing() throws {
        let headersFolders = [AbsolutePath("/headers")]
        let pbxproj = PBXProj()

        let pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)
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
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let testFile = PBXFileReference()
        pbxproj.add(object: testFile)
        let wakaFile = PBXFileReference()
        pbxproj.add(object: wakaFile)
        fileElements.products["waka.framework"] = wakaFile
        fileElements.elements[AbsolutePath("/test.framework")] = testFile

        try subject.generateLinkingPhase(dependencies: dependencies,
                                         pbxTarget: pbxTarget,
                                         pbxproj: pbxproj,
                                         fileElements: fileElements)

        let buildPhase: PBXFrameworksBuildPhase? = pbxTarget.buildPhases.last as? PBXFrameworksBuildPhase

        let testBuildFile: PBXBuildFile? = buildPhase?.files.first
        let wakaBuildFile: PBXBuildFile? = buildPhase?.files.last

        XCTAssertEqual(testBuildFile?.file, testFile)
        XCTAssertEqual(wakaBuildFile?.file, wakaFile)
    }

    func test_generateLinkingPhase_throws_whenFileReferenceIsMissing() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.absolute(AbsolutePath("/test.framework")))
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateLinkingPhase(dependencies: dependencies,
                                                              pbxTarget: pbxTarget,
                                                              pbxproj: pbxproj,
                                                              fileElements: fileElements)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingReference(path: AbsolutePath("/test.framework")))
        }
    }

    func test_generateLinkingPhase_throws_whenProductIsMissing() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.product("waka.framework"))
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateLinkingPhase(dependencies: dependencies,
                                                              pbxTarget: pbxTarget,
                                                              pbxproj: pbxproj,
                                                              fileElements: fileElements)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingProduct(name: "waka.framework"))
        }
    }
}
