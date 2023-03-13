import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class LinkGeneratorPathTests: TuistUnitTestCase {
    func test_xcodeValue() {
        let path = try! AbsolutePath(validating: "/my-path")
        XCTAssertEqual(LinkGeneratorPath.absolutePath(path).xcodeValue(sourceRootPath: .root), "$(SRCROOT)/my-path")
        XCTAssertEqual(
            LinkGeneratorPath.string("$(DEVELOPER_FRAMEWORKS_DIR)").xcodeValue(sourceRootPath: .root),
            "$(DEVELOPER_FRAMEWORKS_DIR)"
        )
    }
}

final class LinkGeneratorTests: XCTestCase {
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
        XCTAssertEqual(
            LinkGeneratorError.missingProduct(name: "name").description,
            "Couldn't find a reference for the product name."
        )
        XCTAssertEqual(
            LinkGeneratorError.missingReference(path: try AbsolutePath(validating: "/")).description,
            "Couldn't find a reference for the file at path /."
        )
        XCTAssertEqual(
            LinkGeneratorError.missingConfigurationList(targetName: "target").description,
            "The target target doesn't have a configuration list."
        )
    }

    func test_linkGeneratorError_type() {
        XCTAssertEqual(LinkGeneratorError.missingProduct(name: "name").type, .bug)
        XCTAssertEqual(LinkGeneratorError.missingReference(path: try AbsolutePath(validating: "/")).type, .bug)
        XCTAssertEqual(LinkGeneratorError.missingConfigurationList(targetName: "target").type, .bug)
    }

    func test_generateEmbedPhase() throws {
        // Given
        var dependencies: Set<GraphDependencyReference> = []
        dependencies.insert(GraphDependencyReference.testFramework())
        dependencies.insert(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let fileElements = ProjectFileElements()
        let wakaFile = PBXFileReference()
        pbxproj.add(object: wakaFile)
        fileElements.products["Test"] = wakaFile
        let sourceRootPath = try AbsolutePath(validating: "/")
        embedScriptGenerator.scriptStub = .success(EmbedScript(
            script: "script",
            inputPaths: [RelativePath("frameworks/A.framework")],
            outputPaths: ["output/A.framework"]
        ))

        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedEmbeddableFrameworksResult = dependencies

        // When
        try subject.generateEmbedPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let scriptBuildPhase: PBXShellScriptBuildPhase? = pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase
        XCTAssertEqual(scriptBuildPhase?.name, "Embed Precompiled Frameworks")
        XCTAssertEqual(scriptBuildPhase?.shellScript, "script")
        XCTAssertEqual(scriptBuildPhase?.inputPaths, ["$(SRCROOT)/frameworks/A.framework"])
        XCTAssertEqual(scriptBuildPhase?.outputPaths, ["output/A.framework"])

        let embedBuildPhase = try XCTUnwrap(pbxTarget.embedFrameworksBuildPhases().first)
        XCTAssertEqual(embedBuildPhase.name, "Embed Frameworks")
        XCTAssertEqual(embedBuildPhase.dstPath, "")
        XCTAssertEqual(embedBuildPhase.dstSubfolderSpec, .frameworks)
        XCTAssertEqual(embedBuildPhase.files?.map(\.file), [
            wakaFile,
        ])
        XCTAssertEqual(embedBuildPhase.files?.compactMap { $0.settings as? [String: [String]] }, [
            ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]],
        ])
    }

    func test_generateEmbedPhaseWithNoEmbeddableFrameworks() throws {
        // Given
        var dependencies: Set<GraphDependencyReference> = []
        dependencies.insert(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let fileElements = ProjectFileElements()
        let wakaFile = PBXFileReference()
        pbxproj.add(object: wakaFile)
        fileElements.products["Test"] = wakaFile
        let sourceRootPath = try AbsolutePath(validating: "/")

        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedEmbeddableFrameworksResult = dependencies

        // When
        try subject.generateEmbedPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let scriptBuildPhase: PBXShellScriptBuildPhase? = pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase
        XCTAssertNil(scriptBuildPhase)

        let embedBuildPhase = try XCTUnwrap(pbxTarget.embedFrameworksBuildPhases().first)
        XCTAssertEqual(embedBuildPhase.name, "Embed Frameworks")
        XCTAssertEqual(embedBuildPhase.dstPath, "")
        XCTAssertEqual(embedBuildPhase.dstSubfolderSpec, .frameworks)
        XCTAssertEqual(embedBuildPhase.files?.map(\.file), [
            wakaFile,
        ])
        XCTAssertEqual(embedBuildPhase.files?.compactMap { $0.settings as? [String: [String]] }, [
            ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]],
        ])
    }

    func test_generateEmbedPhase_includesSymbols_when_nonTestTarget() throws {
        try Product.allCases.filter { !$0.testsBundle }.forEach { product in
            // Given

            var dependencies: Set<GraphDependencyReference> = []
            dependencies.insert(GraphDependencyReference.testFramework())
            dependencies.insert(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
            let pbxproj = PBXProj()
            let (pbxTarget, target) = createTargets(product: product)
            let fileElements = ProjectFileElements()
            let wakaFile = PBXFileReference()
            pbxproj.add(object: wakaFile)
            fileElements.products["Test"] = wakaFile
            let sourceRootPath = try AbsolutePath(validating: "/")
            embedScriptGenerator.scriptStub = .success(EmbedScript(
                script: "script",
                inputPaths: [RelativePath("frameworks/A.framework")],
                outputPaths: ["output/A.framework"]
            ))
            let path = try AbsolutePath(validating: "/path/")
            let graphTraverser = MockGraphTraverser()
            graphTraverser.stubbedEmbeddableFrameworksResult = dependencies

            // When
            try subject.generateEmbedPhase(
                target: target,
                pbxTarget: pbxTarget,
                pbxproj: pbxproj,
                fileElements: fileElements,
                sourceRootPath: sourceRootPath,
                path: path,
                graphTraverser: graphTraverser
            )

            XCTAssert(
                embedScriptGenerator.scriptArgs.last?.2 == true,
                "Expected `includeSymbolsInFileLists == true` for product `\(product)`"
            )
        }
    }

    func test_generateEmbedPhase_doesNot_includesSymbols_when_testTarget() throws {
        try Product.allCases.filter(\.testsBundle).forEach { product in
            // Given

            var dependencies: Set<GraphDependencyReference> = []
            dependencies.insert(GraphDependencyReference.testFramework())
            dependencies.insert(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
            let pbxproj = PBXProj()
            let (pbxTarget, target) = createTargets(product: product)
            let fileElements = ProjectFileElements()
            let wakaFile = PBXFileReference()
            pbxproj.add(object: wakaFile)
            fileElements.products["Test"] = wakaFile
            let sourceRootPath = try AbsolutePath(validating: "/")
            embedScriptGenerator.scriptStub = .success(EmbedScript(
                script: "script",
                inputPaths: [RelativePath("frameworks/A.framework")],
                outputPaths: ["output/A.framework"]
            ))
            let path = try AbsolutePath(validating: "/path/")
            let graphTraverser = MockGraphTraverser()
            graphTraverser.stubbedEmbeddableFrameworksResult = dependencies

            // When
            try subject.generateEmbedPhase(
                target: target,
                pbxTarget: pbxTarget,
                pbxproj: pbxproj,
                fileElements: fileElements,
                sourceRootPath: sourceRootPath,
                path: path,
                graphTraverser: graphTraverser
            )

            XCTAssert(
                embedScriptGenerator.scriptArgs.last?.2 == false,
                "Expected `includeSymbolsInFileLists == false` for product `\(product)`"
            )
        }
    }

    func test_generateEmbedPhase_throws_when_aProductIsMissing() throws {
        var dependencies: Set<GraphDependencyReference> = []
        dependencies.insert(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let fileElements = ProjectFileElements()
        let sourceRootPath = try AbsolutePath(validating: "/")
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedEmbeddableFrameworksResult = dependencies

        XCTAssertThrowsError(try subject.generateEmbedPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingProduct(name: "Test"))
        }
    }

    func test_generateEmbedPhase_setupEmbedFrameworksBuildPhase_whenXCFrameworkIsPresent() throws {
        // Given
        var dependencies: Set<GraphDependencyReference> = []
        dependencies.insert(GraphDependencyReference.testXCFramework(path: "/Frameworks/Test.xcframework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let sourceRootPath = try AbsolutePath(validating: "/")

        let group = PBXGroup()
        pbxproj.add(object: group)

        let fileAbsolutePath = try AbsolutePath(validating: "/Frameworks/Test.xcframework")
        let fileElements = createFileElements(fileAbsolutePath: fileAbsolutePath)
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedEmbeddableFrameworksResult = dependencies

        // When
        try subject.generateEmbedPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

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
            try AbsolutePath(validating: "/path/Dependencies/Frameworks/"),
            try AbsolutePath(validating: "/path/Dependencies/XCFrameworks/"),
        ].shuffled()
        let sourceRootPath = try AbsolutePath(validating: "/path")
        let xcodeprojElements = createXcodeprojElements()
        xcodeprojElements.config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] = "my/custom/path"
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedRunPathSearchPathsResult = Set(paths)

        // When
        try subject.setupRunPathSearchPaths(
            target: target,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let config = xcodeprojElements.config
        XCTAssertEqual(config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] as? [String], [
            "$(inherited)",
            "my/custom/path",
            "$(SRCROOT)/Dependencies/Frameworks",
            "$(SRCROOT)/Dependencies/XCFrameworks",
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
            GraphDependencyReference.testSDK(path: "/XCTest.framework", source: .developer),
            GraphDependencyReference.testProduct(target: "Foo", productName: "Foo.framework"),
        ].shuffled()
        let sourceRootPath = try AbsolutePath(validating: "/path")
        let xcodeprojElements = createXcodeprojElements()
        xcodeprojElements.config.buildSettings["FRAMEWORK_SEARCH_PATHS"] = "my/custom/path"
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedSearchablePathDependenciesResult = Set(dependencies)
        // When
        try subject.setupFrameworkSearchPath(
            target: target,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let config = xcodeprojElements.config
        XCTAssertEqual(config.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? [String], [
            "$(inherited)",
            "my/custom/path",
            "$(PLATFORM_DIR)/Developer/Library/Frameworks",
            "$(SRCROOT)/Dependencies/Frameworks",
            "$(SRCROOT)/Dependencies/Libraries",
            "$(SRCROOT)/Dependencies/XCFrameworks",
        ])
    }

    func test_setupHeadersSearchPath() throws {
        let headersFolders = [try AbsolutePath(validating: "/headers")]
        let pbxproj = PBXProj()

        let pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)

        let configurationList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configurationList)
        pbxTarget.buildConfigurationList = configurationList

        let config = XCBuildConfiguration(name: "Debug")
        pbxproj.add(object: config)
        configurationList.buildConfigurations.append(config)

        let sourceRootPath = try AbsolutePath(validating: "/")
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLibrariesPublicHeadersFoldersResult = Set(headersFolders)

        try subject.setupHeadersSearchPath(
            target: target,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        let expected = ["$(inherited)", "$(SRCROOT)/headers"]
        XCTAssertEqual(config.buildSettings["HEADER_SEARCH_PATHS"] as? [String], expected)
    }

    func test_setupHeadersSearchPaths_extendCustomSettings() throws {
        // Given
        let searchPaths = [
            try AbsolutePath(validating: "/path/to/libraries"),
            try AbsolutePath(validating: "/path/to/other/libraries"),
        ]
        let sourceRootPath = try AbsolutePath(validating: "/path")
        let xcodeprojElements = createXcodeprojElements()
        xcodeprojElements.config.buildSettings["HEADER_SEARCH_PATHS"] = "my/custom/path"
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLibrariesPublicHeadersFoldersResult = Set(searchPaths)

        // When
        try subject.setupHeadersSearchPath(
            target: target,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let config = xcodeprojElements.config
        XCTAssertEqual(config.buildSettings["HEADER_SEARCH_PATHS"] as? [String], [
            "$(inherited)",
            "my/custom/path",
            "$(SRCROOT)/to/libraries",
            "$(SRCROOT)/to/other/libraries",
        ])
    }

    func test_setupHeadersSearchPaths_mergesDuplicates() throws {
        // Given
        let searchPaths = [
            try AbsolutePath(validating: "/path/to/libraries"),
            try AbsolutePath(validating: "/path/to/libraries"),
            try AbsolutePath(validating: "/path/to/libraries"),
        ]
        let sourceRootPath = try AbsolutePath(validating: "/path")
        let xcodeprojElements = createXcodeprojElements()
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLibrariesPublicHeadersFoldersResult = Set(searchPaths)

        // When
        try subject.setupHeadersSearchPath(
            target: target,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let config = xcodeprojElements.config
        XCTAssertEqual(config.buildSettings["HEADER_SEARCH_PATHS"] as? [String], [
            "$(inherited)",
            "$(SRCROOT)/to/libraries",
        ])
    }

    func test_setupHeadersSearchPath_throws_whenTheConfigurationListIsMissing() throws {
        let headersFolders = [try AbsolutePath(validating: "/headers")]
        let pbxproj = PBXProj()

        let pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)
        let sourceRootPath = try AbsolutePath(validating: "/")
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLibrariesPublicHeadersFoldersResult = Set(headersFolders)

        XCTAssertThrowsError(try subject.setupHeadersSearchPath(
            target: target,
            pbxTarget: pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingConfigurationList(targetName: pbxTarget.name))
        }
    }

    func test_setupLibrarySearchPaths_multiplePaths() throws {
        // Given
        let searchPaths = [
            try AbsolutePath(validating: "/path/to/libraries"),
            try AbsolutePath(validating: "/path/to/other/libraries"),
        ]
        let sourceRootPath = try AbsolutePath(validating: "/path")
        let xcodeprojElements = createXcodeprojElements()
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLibrariesSearchPathsResult = Set(searchPaths)

        // When
        try subject.setupLibrarySearchPaths(
            target: target,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let config = xcodeprojElements.config
        let expected = ["$(inherited)", "$(SRCROOT)/to/libraries", "$(SRCROOT)/to/other/libraries"]
        XCTAssertEqual(config.buildSettings["LIBRARY_SEARCH_PATHS"] as? [String], expected)
    }

    func test_setupLibrarySearchPaths_noPaths() throws {
        // Given
        let searchPaths: [AbsolutePath] = []
        let sourceRootPath = try AbsolutePath(validating: "/path")
        let xcodeprojElements = createXcodeprojElements()
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLibrariesSearchPathsResult = Set(searchPaths)

        // When
        try subject.setupLibrarySearchPaths(
            target: target,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let config = xcodeprojElements.config
        XCTAssertNil(config.buildSettings["LIBRARY_SEARCH_PATHS"])
    }

    func test_setupSwiftIncludePaths_multiplePaths() throws {
        // Given
        let searchPaths = [
            try AbsolutePath(validating: "/path/to/libraries"),
            try AbsolutePath(validating: "/path/to/other/libraries"),
        ]
        let sourceRootPath = try AbsolutePath(validating: "/path")
        let xcodeprojElements = createXcodeprojElements()
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLibrariesSwiftIncludePathsResult = Set(searchPaths)

        // When
        try subject.setupSwiftIncludePaths(
            target: target,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let config = xcodeprojElements.config
        let expected = ["$(inherited)", "$(SRCROOT)/to/libraries", "$(SRCROOT)/to/other/libraries"]
        XCTAssertEqual(config.buildSettings["SWIFT_INCLUDE_PATHS"] as? [String], expected)
    }

    func test_setupSwiftIncludePaths_noPaths() throws {
        // Given
        let searchPaths: [AbsolutePath] = []
        let sourceRootPath = try AbsolutePath(validating: "/path")
        let xcodeprojElements = createXcodeprojElements()
        let target = Target.test()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLibrariesSwiftIncludePathsResult = Set(searchPaths)

        // When
        try subject.setupSwiftIncludePaths(
            target: target,
            pbxTarget: xcodeprojElements.pbxTarget,
            sourceRootPath: sourceRootPath,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let config = xcodeprojElements.config
        XCTAssertNil(config.buildSettings["SWIFT_INCLUDE_PATHS"])
    }

    func test_generateLinkingPhase() throws {
        var dependencies: Set<GraphDependencyReference> = []
        dependencies.insert(GraphDependencyReference.testFramework(path: "/test.framework"))
        dependencies.insert(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let fileElements = ProjectFileElements()
        let testFile = PBXFileReference()
        pbxproj.add(object: testFile)
        let wakaFile = PBXFileReference()
        pbxproj.add(object: wakaFile)
        fileElements.products["Test"] = wakaFile
        fileElements.elements[try AbsolutePath(validating: "/test.framework")] = testFile
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLinkableDependenciesResult = dependencies

        try subject.generateLinkingPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )

        let buildPhase = try pbxTarget.frameworksBuildPhase()

        let testBuildFile: PBXBuildFile? = buildPhase?.files?.first
        let wakaBuildFile: PBXBuildFile? = buildPhase?.files?.last

        XCTAssertEqual(testBuildFile?.file, testFile)
        XCTAssertEqual(wakaBuildFile?.file, wakaFile)
    }

    func test_generateLinkingPhase_throws_whenFileReferenceIsMissing() throws {
        var dependencies: Set<GraphDependencyReference> = []
        dependencies.insert(GraphDependencyReference.testFramework(path: "/test.framework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let fileElements = ProjectFileElements()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLinkableDependenciesResult = dependencies

        XCTAssertThrowsError(try subject.generateLinkingPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )) {
            XCTAssertEqual(
                $0 as? LinkGeneratorError,
                LinkGeneratorError.missingReference(path: try! AbsolutePath(validating: "/test.framework"))
            )
        }
    }

    func test_generateLinkingPhase_throws_whenProductIsMissing() throws {
        var dependencies: Set<GraphDependencyReference> = []
        dependencies.insert(GraphDependencyReference.product(target: "Test", productName: "Test.framework"))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let fileElements = ProjectFileElements()
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLinkableDependenciesResult = dependencies

        XCTAssertThrowsError(try subject.generateLinkingPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )) {
            XCTAssertEqual($0 as? LinkGeneratorError, LinkGeneratorError.missingProduct(name: "Test"))
        }
    }

    func test_generateLinkingPhase_sdk() throws {
        // Given
        var dependencies: Set<GraphDependencyReference> = []
        dependencies.insert(GraphDependencyReference.sdk(path: "/Strong/Foo.framework", status: .required, source: .developer))
        dependencies.insert(GraphDependencyReference.sdk(path: "/Weak/Bar.framework", status: .optional, source: .developer))
        let pbxproj = PBXProj()
        let (pbxTarget, target) = createTargets(product: .framework)
        let fileElements = ProjectFileElements()
        let requiredFile = PBXFileReference(name: "required")
        let optionalFile = PBXFileReference(name: "optional")
        fileElements.sdks["/Strong/Foo.framework"] = requiredFile
        fileElements.sdks["/Weak/Bar.framework"] = optionalFile
        let path = try AbsolutePath(validating: "/path/")
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedLinkableDependenciesResult = dependencies

        // When
        try subject.generateLinkingPhase(
            target: target,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let buildPhase = try pbxTarget.frameworksBuildPhase()

        XCTAssertNotNil(buildPhase)
        XCTAssertEqual(buildPhase?.files?.map(\.file), [
            requiredFile,
            optionalFile,
        ])
        XCTAssertEqual(buildPhase?.files?.map { $0.settings?.description }, [
            nil,
            "[\"ATTRIBUTES\": [\"Weak\"]]",
        ])
    }

    func test_generateCopyProductsBuildPhase_staticTargetDependsOnStaticProducts() throws {
        // Given
        let path = try AbsolutePath(validating: "/path/")
        var dependencies: Set<GraphDependencyReference> = []
        dependencies
            .insert(GraphDependencyReference.testProduct(target: "StaticDependency", productName: "libStaticDependency.a"))
        let staticDependency = Target.test(name: "StaticDependency", product: .staticLibrary)
        let target = Target.test()
        let graphTraverser = MockGraphTraverser()
        graphTraverser.stubbedCopyProductDependenciesResult = dependencies
        let fileElements = createProjectFileElements(for: [staticDependency])
        let xcodeProjElements = createXcodeprojElements()

        // When
        try subject.generateCopyProductsBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: xcodeProjElements.pbxTarget,
            pbxproj: xcodeProjElements.pbxproj,
            fileElements: fileElements
        )

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

    func test_generateCopyProductsBuildPhase_dynamicTargetDependsOnStaticProducts() throws {
        // Given
        let path = try AbsolutePath(validating: "/path/")
        let staticDependency = Target.test(name: "StaticDependency", product: .staticLibrary)
        let target = Target.test(name: "Dynamic", product: .framework)
        let graph = Graph.test(
            projects: [path: .test(path: path)],
            targets: [
                path: [
                    target.name: target,
                    staticDependency.name: staticDependency,
                ],
            ],
            dependencies: [
                .target(name: target.name, path: path): [
                    .target(name: staticDependency.name, path: path),
                ],
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)
        let fileElements = createProjectFileElements(for: [staticDependency])
        let xcodeProjElements = createXcodeprojElements()

        // When
        try subject.generateCopyProductsBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: xcodeProjElements.pbxTarget,
            pbxproj: xcodeProjElements.pbxproj,
            fileElements: fileElements
        )

        // Then
        let copyProductsPhase = xcodeProjElements
            .pbxTarget
            .buildPhases
            .compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first(where: { $0.name() == "Dependencies" })
        XCTAssertNil(copyProductsPhase)
    }

    func test_generateCopyProductsBuildPhase_resourceBundles() throws {
        // Given
        let path = try AbsolutePath(validating: "/path/")
        let resourceBundle = Target.test(name: "ResourceBundle", product: .bundle)
        let target = Target.test(name: "Target", product: .app)
        let graph = Graph.test(
            projects: [path: .test(path: path)],
            targets: [
                path: [
                    target.name: target,
                    resourceBundle.name: resourceBundle,
                ],
            ],
            dependencies: [
                .target(name: target.name, path: path): [
                    .target(name: resourceBundle.name, path: path),
                ],
            ]
        )
        let fileElements = createProjectFileElements(for: [resourceBundle])
        let xcodeProjElements = createXcodeprojElements()
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateCopyProductsBuildPhase(
            path: path,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: xcodeProjElements.pbxTarget,
            pbxproj: xcodeProjElements.pbxproj,
            fileElements: fileElements
        )

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

        return XcodeprojElements(
            pbxproj: pbxproj,
            pbxTarget: pbxTarget,
            config: config
        )
    }

    func createProjectFileElements(for targets: [Target]) -> ProjectFileElements {
        let projectFileElements = ProjectFileElements()
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
