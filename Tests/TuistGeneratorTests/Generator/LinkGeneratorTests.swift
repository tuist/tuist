import Basic
import Foundation
import XcodeProj
import XCTest
@testable import TuistGenerator

final class LinkGeneratorErrorTests: XCTestCase {
    var embedScriptGenerator: MockEmbedScriptGenerator!
    var subject: LinkGenerator!

    override func setUp() {
        super.setUp()
        embedScriptGenerator = MockEmbedScriptGenerator()
        subject = LinkGenerator(embedScriptGenerator: embedScriptGenerator)
    }

    override func tearDown() {
        subject = nil
        embedScriptGenerator = nil
        super.tearDown()
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
        // Given
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.absolute(AbsolutePath("/test.framework")))
        dependencies.append(DependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let wakaFile = PBXFileReference()
        pbxproj.add(object: wakaFile)
        fileElements.products["Test"] = wakaFile
        let sourceRootPath = AbsolutePath("/")
        embedScriptGenerator.scriptStub = .success(EmbedScript(script: "script",
                                                               inputPaths: [RelativePath("frameworks/A.framework")],
                                                               outputPaths: ["output/A.framework"]))

        // When
        try subject.generateEmbedPhase(dependencies: dependencies,
                                       pbxTarget: pbxTarget,
                                       pbxproj: pbxproj,
                                       fileElements: fileElements,
                                       sourceRootPath: sourceRootPath)

        // Then
        let scriptBuildPhase: PBXShellScriptBuildPhase? = pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase
        XCTAssertEqual(scriptBuildPhase?.name, "Embed Precompiled Frameworks")
        XCTAssertEqual(scriptBuildPhase?.shellScript, "script")
        XCTAssertEqual(scriptBuildPhase?.inputPaths, ["frameworks/A.framework"])
        XCTAssertEqual(scriptBuildPhase?.outputPaths, ["output/A.framework"])

        let copyBuildPhase: PBXCopyFilesBuildPhase? = pbxTarget.buildPhases.last as? PBXCopyFilesBuildPhase
        XCTAssertEqual(copyBuildPhase?.name, "Embed Frameworks")
        let wakaBuildFile: PBXBuildFile? = copyBuildPhase?.files?.first
        XCTAssertEqual(wakaBuildFile?.file, wakaFile)
        let settings: [String: [String]]? = wakaBuildFile?.settings as? [String: [String]]
        XCTAssertEqual(settings, ["ATTRIBUTES": ["CodeSignOnCopy"]])
    }

    func test_generateEmbedPhase_throws_when_aProductIsMissing() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let sourceRootPath = AbsolutePath("/")

        XCTAssertThrowsError(try subject.generateEmbedPhase(dependencies: dependencies,
                                                            pbxTarget: pbxTarget,
                                                            pbxproj: pbxproj,
                                                            fileElements: fileElements,
                                                            sourceRootPath: sourceRootPath)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingProduct(name: "Test"))
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

        let expected = ["$(inherited)", "$(SRCROOT)/Dependencies", "$(SRCROOT)/Dependencies/C"]
        XCTAssertEqual(debugConfig.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? [String], expected)
        XCTAssertEqual(releaseConfig.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? [String], expected)
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

        let expected = ["$(inherited)", "$(SRCROOT)/headers"]
        XCTAssertEqual(config.buildSettings["HEADER_SEARCH_PATHS"] as? [String], expected)
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

    func test_setupLibrarySearchPaths_multiplePaths() throws {
        // Given
        let searchPaths = [
            AbsolutePath("/path/to/libraries"),
            AbsolutePath("/path/to/other/libraries"),
        ]
        let sourceRootPath = AbsolutePath("/path")
        let xcodeprojElements = createXcodeprojElements()

        // When
        try subject.setupLibrarySearchPaths(searchPaths,
                                            pbxTarget: xcodeprojElements.pbxTarget,
                                            sourceRootPath: sourceRootPath)

        // Then
        let config = xcodeprojElements.config
        let expected = ["$(inherited)", "$(SRCROOT)/to/libraries", "$(SRCROOT)/to/other/libraries"]
        XCTAssertEqual(config.buildSettings["LIBRARY_SEARCH_PATHS"] as? [String], expected)
    }

    func test_setupLibrarySearchPaths_noPaths() throws {
        // Given
        let searchPaths: [AbsolutePath] = []
        let sourceRootPath = AbsolutePath("/path")
        let xcodeprojElements = createXcodeprojElements()

        // When
        try subject.setupLibrarySearchPaths(searchPaths,
                                            pbxTarget: xcodeprojElements.pbxTarget,
                                            sourceRootPath: sourceRootPath)

        // Then
        let config = xcodeprojElements.config
        XCTAssertNil(config.buildSettings["LIBRARY_SEARCH_PATHS"])
    }

    func test_setupSwiftIncludePaths_multiplePaths() throws {
        // Given
        let searchPaths = [
            AbsolutePath("/path/to/libraries"),
            AbsolutePath("/path/to/other/libraries"),
        ]
        let sourceRootPath = AbsolutePath("/path")
        let xcodeprojElements = createXcodeprojElements()

        // When
        try subject.setupSwiftIncludePaths(searchPaths,
                                           pbxTarget: xcodeprojElements.pbxTarget,
                                           sourceRootPath: sourceRootPath)

        // Then
        let config = xcodeprojElements.config
        let expected = ["$(inherited)", "$(SRCROOT)/to/libraries", "$(SRCROOT)/to/other/libraries"]
        XCTAssertEqual(config.buildSettings["SWIFT_INCLUDE_PATHS"] as? [String], expected)
    }

    func test_setupSwiftIncludePaths_noPaths() throws {
        // Given
        let searchPaths: [AbsolutePath] = []
        let sourceRootPath = AbsolutePath("/path")
        let xcodeprojElements = createXcodeprojElements()

        // When
        try subject.setupSwiftIncludePaths(searchPaths,
                                           pbxTarget: xcodeprojElements.pbxTarget,
                                           sourceRootPath: sourceRootPath)

        // Then
        let config = xcodeprojElements.config
        XCTAssertNil(config.buildSettings["SWIFT_INCLUDE_PATHS"])
    }

    func test_generateLinkingPhase() throws {
        var dependencies: [DependencyReference] = []
        dependencies.append(DependencyReference.absolute(AbsolutePath("/test.framework")))
        dependencies.append(DependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let testFile = PBXFileReference()
        pbxproj.add(object: testFile)
        let wakaFile = PBXFileReference()
        pbxproj.add(object: wakaFile)
        fileElements.products["Test"] = wakaFile
        fileElements.elements[AbsolutePath("/test.framework")] = testFile

        try subject.generateLinkingPhase(dependencies: dependencies,
                                         pbxTarget: pbxTarget,
                                         pbxproj: pbxproj,
                                         fileElements: fileElements)

        let buildPhase = try pbxTarget.frameworksBuildPhase()

        let testBuildFile: PBXBuildFile? = buildPhase?.files?.first
        let wakaBuildFile: PBXBuildFile? = buildPhase?.files?.last

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
        dependencies.append(DependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()

        XCTAssertThrowsError(try subject.generateLinkingPhase(dependencies: dependencies,
                                                              pbxTarget: pbxTarget,
                                                              pbxproj: pbxproj,
                                                              fileElements: fileElements)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingProduct(name: "Test"))
        }
    }

    func test_generateLinkingPhase_sdkNodes() throws {
        // Given
        let dependencies: [DependencyReference] = [
            .sdk("/Strong/Foo.framework", .required),
            .sdk("/Weak/Bar.framework", .optional),
        ]
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let requiredFile = PBXFileReference(name: "required")
        let optionalFile = PBXFileReference(name: "optional")
        fileElements.sdks["/Strong/Foo.framework"] = requiredFile
        fileElements.sdks["/Weak/Bar.framework"] = optionalFile

        // When
        try subject.generateLinkingPhase(dependencies: dependencies,
                                         pbxTarget: pbxTarget,
                                         pbxproj: pbxproj,
                                         fileElements: fileElements)

        // Then
        let buildPhase = try pbxTarget.frameworksBuildPhase()

        XCTAssertNotNil(buildPhase)
        XCTAssertEqual(buildPhase?.files?.map { $0.file }, [
            requiredFile,
            optionalFile,
        ])
        XCTAssertEqual(buildPhase?.files?.map { $0.settings?.description }, [
            nil,
            "[\"ATTRIBUTES\": [\"Weak\"]]",
        ])
    }

    func test_generateCopyProductsdBuildPhase_staticTargetDependsOnStaticProducts() throws {
        // Given
        let path = AbsolutePath("/path/")
        let staticDependency = Target.test(name: "StaticDependency", product: .staticLibrary)
        let target = Target.test(name: "Static", product: .staticLibrary)
        let graph = Graph.create(project: .test(path: path),
                                 dependencies: [
                                     (target: target, dependencies: [staticDependency]),
                                     (target: staticDependency, dependencies: []),
                                 ])
        let fileElements = createProjectFileElements(for: [staticDependency])
        let xcodeProjElements = createXcodeprojElements()

        // When
        try subject.generateCopyProductsdBuildPhase(path: path,
                                                    target: target,
                                                    graph: graph,
                                                    pbxTarget: xcodeProjElements.pbxTarget,
                                                    pbxproj: xcodeProjElements.pbxproj,
                                                    fileElements: fileElements)

        // Then
        let copyProductsPhase = xcodeProjElements
            .pbxTarget
            .buildPhases
            .compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first(where: { $0.name() == "Dependencies" })
        XCTAssertEqual(copyProductsPhase?.dstSubfolderSpec, .productsDirectory)

        let buildFiles = copyProductsPhase?.files?.compactMap { $0.file?.path }
        XCTAssertEqual(buildFiles, [
            "libStaticDependency.a",
        ])
    }

    func test_generateCopyProductsdBuildPhase_dynamicTargetDependsOnStaticProducts() throws {
        // Given
        let path = AbsolutePath("/path/")
        let staticDependency = Target.test(name: "StaticDependency", product: .staticLibrary)
        let target = Target.test(name: "Dynamic", product: .framework)
        let graph = Graph.create(project: .test(path: path),
                                 dependencies: [
                                     (target: target, dependencies: [staticDependency]),
                                     (target: staticDependency, dependencies: []),
                                 ])
        let fileElements = createProjectFileElements(for: [staticDependency])
        let xcodeProjElements = createXcodeprojElements()

        // When
        try subject.generateCopyProductsdBuildPhase(path: path,
                                                    target: target,
                                                    graph: graph,
                                                    pbxTarget: xcodeProjElements.pbxTarget,
                                                    pbxproj: xcodeProjElements.pbxproj,
                                                    fileElements: fileElements)

        // Then
        let copyProductsPhase = xcodeProjElements
            .pbxTarget
            .buildPhases
            .compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first(where: { $0.name() == "Dependencies" })
        XCTAssertNil(copyProductsPhase)
    }

    func test_generateCopyProductsdBuildPhase_resourceBundles() throws {
        // Given
        let path = AbsolutePath("/path/")
        let resourceBundle = Target.test(name: "ResourceBundle", product: .bundle)
        let target = Target.test(name: "Target", product: .app)
        let graph = Graph.create(project: .test(path: path),
                                 dependencies: [
                                     (target: target, dependencies: [resourceBundle]),
                                     (target: resourceBundle, dependencies: []),
                                 ])
        let fileElements = createProjectFileElements(for: [resourceBundle])
        let xcodeProjElements = createXcodeprojElements()

        // When
        try subject.generateCopyProductsdBuildPhase(path: path,
                                                    target: target,
                                                    graph: graph,
                                                    pbxTarget: xcodeProjElements.pbxTarget,
                                                    pbxproj: xcodeProjElements.pbxproj,
                                                    fileElements: fileElements)

        // Then
        let copyProductsPhase = xcodeProjElements
            .pbxTarget
            .buildPhases
            .compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first(where: { $0.name() == "Dependencies" })
        XCTAssertEqual(copyProductsPhase?.dstSubfolderSpec, .productsDirectory)

        let buildFiles = copyProductsPhase?.files?.compactMap { $0.file?.path }
        XCTAssertEqual(buildFiles, [
            "ResourceBundle.bundle",
        ])
    }

    // MARK: - Helpers

    struct XcodeprojElements {
        var pbxproj: PBXProj
        var pbxTarget: PBXNativeTarget
        var config: XCBuildConfiguration
    }

    func createXcodeprojElements() -> XcodeprojElements {
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)

        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)
        pbxTarget.buildConfigurationList = configurationList

        let config = XCBuildConfiguration(name: "Debug")
        pbxproj.add(object: config)
        configurationList.buildConfigurations.append(config)

        return XcodeprojElements(pbxproj: pbxproj,
                                 pbxTarget: pbxTarget,
                                 config: config)
    }

    func createProjectFileElements(for targets: [Target]) -> ProjectFileElements {
        let projectFileElements = ProjectFileElements(playgrounds: MockPlaygrounds())
        targets.forEach {
            projectFileElements.products[$0.name] = PBXFileReference(path: $0.productNameWithExtension)
        }

        return projectFileElements
    }
}
