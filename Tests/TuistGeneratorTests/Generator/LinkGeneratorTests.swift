import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class LinkGeneratorPathTests: TuistUnitTestCase {
    func test_xcodeValue() {
        let path = AbsolutePath("/my-path")
        XCTAssertEqual(LinkGeneratorPath.absolutePath(path).xcodeValue(sourceRootPath: .root), "$(SRCROOT)/my-path")
        XCTAssertEqual(LinkGeneratorPath.string("$(DEVELOPER_FRAMEWORKS_DIR)").xcodeValue(sourceRootPath: .root), "$(DEVELOPER_FRAMEWORKS_DIR)")
    }
}

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
        var dependencies: [GraphDependencyReference] = []
        dependencies.append(GraphDependencyReference.testFramework())
        dependencies.append(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
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
                                       target: target,
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
        XCTAssertEqual(settings, ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]])
    }

    func test_generateEmbedPhase_includesSymbols_when_nonTestTarget() throws {
        try Product.allCases.filter { !$0.testsBundle }.forEach { product in
            // Given

            var dependencies: [GraphDependencyReference] = []
            dependencies.append(GraphDependencyReference.testFramework())
            dependencies.append(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
            let pbxproj = PBXProj()
            let (pbxTarget, target) = createTargets(product: product)
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
                                           target: target,
                                           pbxTarget: pbxTarget,
                                           pbxproj: pbxproj,
                                           fileElements: fileElements,
                                           sourceRootPath: sourceRootPath)

            XCTAssert(embedScriptGenerator.scriptArgs.last?.2 == true, "Expected `includeSymbolsInFileLists == true` for product `\(product)`")
        }
    }

    func test_generateEmbedPhase_doesNot_includesSymbols_when_testTarget() throws {
        try Product.allCases.filter { $0.testsBundle }.forEach { product in
            // Given

            var dependencies: [GraphDependencyReference] = []
            dependencies.append(GraphDependencyReference.testFramework())
            dependencies.append(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
            let pbxproj = PBXProj()
            let (pbxTarget, target) = createTargets(product: product)
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
                                           target: target,
                                           pbxTarget: pbxTarget,
                                           pbxproj: pbxproj,
                                           fileElements: fileElements,
                                           sourceRootPath: sourceRootPath)

            XCTAssert(embedScriptGenerator.scriptArgs.last?.2 == false, "Expected `includeSymbolsInFileLists == false` for product `\(product)`")
        }
    }

    func test_generateEmbedPhase_throws_when_aProductIsMissing() throws {
        var dependencies: [GraphDependencyReference] = []
        dependencies.append(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let fileElements = ProjectFileElements()
        let sourceRootPath = AbsolutePath("/")

        XCTAssertThrowsError(try subject.generateEmbedPhase(dependencies: dependencies,
                                                            target: target,
                                                            pbxTarget: pbxTarget,
                                                            pbxproj: pbxproj,
                                                            fileElements: fileElements,
                                                            sourceRootPath: sourceRootPath)) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingProduct(name: "Test"))
        }
    }

    func test_generateEmbedPhase_setupEmbedFrameworksBuildPhase_whenXCFrameworkIsPresent() throws {
        // Given
        var dependencies: [GraphDependencyReference] = []
        dependencies.append(GraphDependencyReference.testXCFramework(path: "/Frameworks/Test.xcframework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let sourceRootPath = AbsolutePath("/")

        let group = PBXGroup()
        pbxproj.add(object: group)

        let fileAbsolutePath = AbsolutePath("/Frameworks/Test.xcframework")
        let fileElements = createFileElements(fileAbsolutePath: fileAbsolutePath)

        // When
        try subject.generateEmbedPhase(dependencies: dependencies,
                                       target: target,
                                       pbxTarget: pbxTarget,
                                       pbxproj: pbxproj,
                                       fileElements: fileElements,
                                       sourceRootPath: sourceRootPath)

        // Then
        let copyBuildPhase = try XCTUnwrap(pbxTarget.embedFrameworksBuildPhases().first)
        XCTAssertEqual(copyBuildPhase.name, "Embed Frameworks")
        let buildFiles = try XCTUnwrap(copyBuildPhase.files)
        XCTAssertEqual(buildFiles.map { $0.file?.path }, ["Test.xcframework"])
        XCTAssertEqual(buildFiles.map { $0.settings as? [String: [String]] }, [
            ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]],
        ])
    }

    func test_setupRunPathSearchPath() throws {
        // Given
        let paths = [
            AbsolutePath("/path/Dependencies/Frameworks/"),
            AbsolutePath("/path/Dependencies/XCFrameworks/"),
        ].shuffled()
        let sourceRootPath = AbsolutePath("/path")
        let xcodeprojElements = createXcodeprojElements()
        xcodeprojElements.config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] = "my/custom/path"

        // When
        try subject.setupRunPathSearchPaths(
            paths,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath
        )

        // Then
        let config = xcodeprojElements.config
        XCTAssertEqual(config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] as? [String], [
            "$(inherited)",
            "$(SRCROOT)/Dependencies/Frameworks",
            "$(SRCROOT)/Dependencies/XCFrameworks",
            "my/custom/path",
        ])
    }

    func test_setupFrameworkSearchPath() throws {
        // Given
        let dependencies = [
            GraphDependencyReference.testFramework(path: "/path/Dependencies/Frameworks/A.framework"),
            GraphDependencyReference.testFramework(path: "/path/Dependencies/Frameworks/B.framework"),
            GraphDependencyReference.testLibrary(path: "/path/Dependencies/Libraries/libC.a"),
            GraphDependencyReference.testLibrary(path: "/path/Dependencies/Libraries/libD.a"),
            GraphDependencyReference.testXCFramework(path: "/path/Dependencies/XCFrameworks/E.xcframework"),
            GraphDependencyReference.testSDK(path: "/libc++.tbd"),
            GraphDependencyReference.testSDK(path: "/CloudKit.framework"),
            GraphDependencyReference.testProduct(target: "Foo", productName: "Foo.framework"),
        ].shuffled()
        let sourceRootPath = AbsolutePath("/path")
        let xcodeprojElements = createXcodeprojElements()
        xcodeprojElements.config.buildSettings["FRAMEWORK_SEARCH_PATHS"] = "my/custom/path"

        // When
        try subject.setupFrameworkSearchPath(dependencies: dependencies,
                                             pbxTarget: xcodeprojElements.pbxTarget,
                                             sourceRootPath: sourceRootPath)

        // Then
        let config = xcodeprojElements.config
        XCTAssertEqual(config.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? [String], [
            "$(DEVELOPER_FRAMEWORKS_DIR)",
            "$(inherited)",
            "$(SRCROOT)/Dependencies/Frameworks",
            "$(SRCROOT)/Dependencies/Libraries",
            "$(SRCROOT)/Dependencies/XCFrameworks",
            "my/custom/path",
        ])
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

    func test_setupHeadersSearchPaths_extendCustomSettings() throws {
        // Given
        let searchPaths = [
            AbsolutePath("/path/to/libraries"),
            AbsolutePath("/path/to/other/libraries"),
        ]
        let sourceRootPath = AbsolutePath("/path")
        let xcodeprojElements = createXcodeprojElements()
        xcodeprojElements.config.buildSettings["HEADER_SEARCH_PATHS"] = "my/custom/path"

        // When
        try subject.setupHeadersSearchPath(searchPaths,
                                           pbxTarget: xcodeprojElements.pbxTarget,
                                           sourceRootPath: sourceRootPath)

        // Then
        let config = xcodeprojElements.config
        XCTAssertEqual(config.buildSettings["HEADER_SEARCH_PATHS"] as? [String], [
            "$(inherited)",
            "$(SRCROOT)/to/libraries",
            "$(SRCROOT)/to/other/libraries",
            "my/custom/path",
        ])
    }

    func test_setupHeadersSearchPaths_mergesDuplicates() throws {
        // Given
        let searchPaths = [
            AbsolutePath("/path/to/libraries"),
            AbsolutePath("/path/to/libraries"),
            AbsolutePath("/path/to/libraries"),
        ]
        let sourceRootPath = AbsolutePath("/path")
        let xcodeprojElements = createXcodeprojElements()

        // When
        try subject.setupHeadersSearchPath(searchPaths,
                                           pbxTarget: xcodeprojElements.pbxTarget,
                                           sourceRootPath: sourceRootPath)

        // Then
        let config = xcodeprojElements.config
        XCTAssertEqual(config.buildSettings["HEADER_SEARCH_PATHS"] as? [String], [
            "$(inherited)",
            "$(SRCROOT)/to/libraries",
        ])
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
        var dependencies: [GraphDependencyReference] = []
        dependencies.append(GraphDependencyReference.testFramework(path: "/test.framework"))
        dependencies.append(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
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
        var dependencies: [GraphDependencyReference] = []
        dependencies.append(GraphDependencyReference.testFramework(path: "/test.framework"))
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
        var dependencies: [GraphDependencyReference] = []
        dependencies.append(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
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
        let dependencies: [GraphDependencyReference] = [
            .sdk(path: "/Strong/Foo.framework", status: .required, source: .developer),
            .sdk(path: "/Weak/Bar.framework", status: .optional, source: .developer),
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

    private func createTargets(product: Product) -> (PBXTarget, Target) {
        return (
            PBXNativeTarget(name: "Test"),
            Target.test(name: "Test", product: product)
        )
    }

    private func createFileElements(fileAbsolutePath: AbsolutePath) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        fileElements.elements[fileAbsolutePath] = PBXFileReference(path: fileAbsolutePath.basename)
        return fileElements
    }
}
