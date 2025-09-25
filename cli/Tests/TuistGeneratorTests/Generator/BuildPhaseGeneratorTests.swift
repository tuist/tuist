import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj
@testable import TuistGenerator
@testable import TuistTesting

struct BuildPhaseGenerationErrorTests {
    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func description_when_missingFileReference() {
        let path = try! AbsolutePath(validating: "/test")
        let expected = "Trying to add a file at path \(path.pathString) to a build phase that hasn't been added to the project."
        #expect(BuildPhaseGenerationError.missingFileReference(path).description == expected)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func type_when_missingFileReference() {
        let path = try! AbsolutePath(validating: "/test")
        #expect(BuildPhaseGenerationError.missingFileReference(path).type == .bug)
    }
}

@Suite
struct BuildPhaseGeneratorTests {
    var subject: BuildPhaseGenerator!

    init() async throws {
        subject = BuildPhaseGenerator()
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateSourcesBuildPhase() async throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let sources: [SourceFile] = [
            SourceFile(path: "/test/file1.swift", compilerFlags: "flag"),
            SourceFile(path: "/test/file2.swift"),
            SourceFile(path: "/test/file3.swift", codeGen: .public),
            SourceFile(path: "/test/file4.swift", codeGen: .private),
            SourceFile(path: "/test/file5.swift", codeGen: .project),
            SourceFile(path: "/test/file6.swift", codeGen: .disabled),
        ]

        let target = Target.test(sources: sources)

        let fileElements = createFileElements(for: sources.map(\.path))

        // When
        try await subject.generateSourcesBuildPhase(
            files: sources,
            coreDataModels: [],
            target: target,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try pbxTarget.sourcesBuildPhase()
        let buildFiles = buildPhase?.files ?? []
        let buildFilesNames = buildFiles.map {
            $0.file?.name
        }

        #expect(buildFilesNames == [
            "file1.swift",
            "file2.swift",
            "file3.swift",
            "file4.swift",
            "file5.swift",
            "file6.swift",
        ])

        let settings = buildFiles.map(\.settings)

        #expect(settings == [
            ["COMPILER_FLAGS": "flag"],
            nil,
            ["ATTRIBUTES": ["codegen"]],
            ["ATTRIBUTES": ["private_codegen"]],
            ["ATTRIBUTES": ["project_codegen"]],
            ["ATTRIBUTES": ["no_codegen"]],
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateSourcesBuildPhase_whenMultiPlatformSourceFiles() async throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let sourceFiles: [SourceFile] = [
            SourceFile(path: "/test/file1.swift"),
            SourceFile(path: "/test/file2.swift", compilationCondition: .when([.ios])),
            SourceFile(path: "/test/file3.swift", compilationCondition: .when([.watchos])),
            SourceFile(path: "/test/file4.swift", compilationCondition: .when([.visionos])),
            SourceFile(path: "/test/file5.swift", compilationCondition: .when([.macos])),
            SourceFile(path: "/test/file6.swift", compilationCondition: .when([.tvos])),
        ]

        let target = Target.test(sources: sourceFiles)

        let fileElements = createFileElements(for: sourceFiles.map(\.path))

        // When
        try await subject.generateSourcesBuildPhase(
            files: sourceFiles,
            coreDataModels: [],
            target: target,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try pbxTarget.sourcesBuildPhase()
        let buildFiles = buildPhase?.files ?? []
        let buildFilesNames = buildFiles.map {
            $0.file?.name
        }

        let buildFilesPlatformFilters = buildFiles.map(\.platformFilters)

        #expect(buildFilesNames == [
            "file1.swift",
            "file2.swift",
            "file3.swift",
            "file4.swift",
            "file5.swift",
            "file6.swift",
        ])

        #expect(buildFilesPlatformFilters == [
            nil, // No platform filter applied, because none request
            nil, // No platform filter applied, because the test target is an iOS target, so no filter necessary
            ["watchos"],
            ["xros"],
            ["macos"],
            ["tvos"],
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateSourcesBuildPhase_whenBundleWithMetalFiles() async throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let sourceFiles: [SourceFile] = [
            SourceFile(path: "/test/resource.metal"),
        ]

        let target = Target.test(product: .bundle, sources: sourceFiles)

        let fileElements = createFileElements(for: sourceFiles.map(\.path))

        // When
        try await subject.generateSourcesBuildPhase(
            files: sourceFiles,
            coreDataModels: [],
            target: target,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try pbxTarget.sourcesBuildPhase()
        let buildFiles = buildPhase?.files ?? []
        let buildFilesNames = buildFiles.map {
            $0.file?.name
        }

        #expect(buildFilesNames == [
            "resource.metal",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func doesntGenerateSourcesBuildPhase_whenWatchKitTarget() async throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let target = Target.test(product: .watch2App)

        // When
        try await subject.generateSourcesBuildPhase(
            files: [],
            coreDataModels: [],
            target: target,
            pbxTarget: pbxTarget,
            fileElements: .init(),
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try pbxTarget.sourcesBuildPhase()

        #expect(buildPhase == nil)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generatesSourcesBuildPhase_whenFramework_withNoSources() async throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let target = Target.test(product: .framework)

        // When
        try await subject.generateSourcesBuildPhase(
            files: [],
            coreDataModels: [],
            target: target,
            pbxTarget: pbxTarget,
            fileElements: .init(),
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try pbxTarget.sourcesBuildPhase()
        let files = try #require(buildPhase?.files)
        #expect(files.isEmpty == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateBuildPhases() async throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let fileElements = ProjectFileElements()
        let graph = Graph.test(path: directory)
        let graphTraverser = GraphTraverser(graph: graph)
        let target = Target(
            name: "Test",
            destinations: .iOS,
            product: .framework,
            productName: nil,
            bundleId: "dev.tuist.test",
            filesGroup: .group(name: "Test"),
            buildableFolders: [
                BuildableFolder(path: directory.appending(component: "Headers"), exceptions: [], resolvedFiles: [
                    BuildableFolderFile(
                        path: directory.appending(components: ["Headers", "Header.h"]),
                        compilerFlags: nil
                    ),
                ]),
            ]
        )

        try await subject.generateBuildPhases(
            path: directory,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        #expect(pbxTarget.buildPhases.first as? PBXHeadersBuildPhase != nil)
    }

    @Test(.withMockedSwiftVersionProvider, .withMockedXcodeController, .inTemporaryDirectory) func generateScripts() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let targetScript = RawScriptBuildPhase(name: "Test", script: "Script", showEnvVarsInLog: true, hashable: false)
        let targetScripts = [targetScript]

        // When
        subject.generateRawScriptBuildPhases(
            targetScripts,
            pbxTarget: target,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try #require(target.buildPhases.first as? PBXShellScriptBuildPhase)
        #expect(buildPhase.name == targetScript.name)
        #expect(buildPhase.shellScript == targetScript.script)
        #expect(buildPhase.shellPath == "/bin/sh")
        #expect(buildPhase.files == [])
        #expect(buildPhase.showEnvVarsInLog == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateScriptsWithCustomShell() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)
        let targetScript = RawScriptBuildPhase(
            name: "Test",
            script: "Script",
            showEnvVarsInLog: true,
            hashable: false,
            shellPath: "/bin/zsh"
        )
        let targetScripts = [targetScript]

        // When
        subject.generateRawScriptBuildPhases(
            targetScripts,
            pbxTarget: target,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try #require(target.buildPhases.first as? PBXShellScriptBuildPhase)
        #expect(buildPhase.shellPath == "/bin/zsh")
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateSourcesBuildPhase_throws_when_theFileReferenceIsMissing() async throws {
        let path = try! AbsolutePath(validating: "/test/file.swift")
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let target = Target.test()
        let fileElements = ProjectFileElements()

        await #expect(throws: BuildPhaseGenerationError.missingFileReference(path), performing: {
            try await subject.generateSourcesBuildPhase(
                files: [SourceFile(path: path, compilerFlags: nil)],
                coreDataModels: [],
                target: target,
                pbxTarget: pbxTarget,
                fileElements: fileElements,
                pbxproj: pbxproj
            )
        })
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateSourcesBuildPhase_withDocCArchive() async throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let sources: [SourceFile] = [
            SourceFile(path: "/path/sources/Foo.swift", compilerFlags: nil),
            SourceFile(path: "/path/sources/Doc.docc", compilerFlags: nil),
        ]
        let target = Target.test(sources: sources)

        let fileElements = createFileElements(for: sources.map(\.path))

        // When
        try await subject.generateSourcesBuildPhase(
            files: sources,
            coreDataModels: [],
            target: target,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try pbxTarget.sourcesBuildPhase()
        let buildFiles = buildPhase?.files ?? []
        let buildFilesNames = buildFiles.map {
            $0.file?.name
        }

        #expect(buildFilesNames == ["Doc.docc", "Foo.swift"])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateSourcesBuildPhase_whenLocalizedFile() async throws {
        // Given
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let sources: [SourceFile] = [
            SourceFile(path: "/path/sources/Base.lproj/OTTSiriExtension.intentdefinition", compilerFlags: nil),
            SourceFile(path: "/path/sources/en.lproj/OTTSiriExtension.intentdefinition", compilerFlags: nil),
        ]
        let target = Target.test(sources: sources)

        let fileElements = createLocalizedResourceFileElements(for: [
            "/path/sources/OTTSiriExtension.intentdefinition",
        ])

        // When
        try await subject.generateSourcesBuildPhase(
            files: sources,
            coreDataModels: [],
            target: target,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try pbxTarget.sourcesBuildPhase()
        let buildFiles = buildPhase?.files ?? []

        #expect(buildFiles.map(\.file) == [
            fileElements.elements["/path/sources/OTTSiriExtension.intentdefinition"],
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateSourcesBuildPhase_throws_whenLocalizedFileAndFileReferenceIsMissing() async throws {
        let path = try! AbsolutePath(validating: "/test/Base.lproj/file.intentdefinition")
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let target = Target.test()
        let fileElements = ProjectFileElements()

        await #expect(throws: BuildPhaseGenerationError.missingFileReference(path), performing: {
            try await subject.generateSourcesBuildPhase(
                files: [SourceFile(path: path, compilerFlags: nil)],
                coreDataModels: [],
                target: target,
                pbxTarget: pbxTarget,
                fileElements: fileElements,
                pbxproj: pbxproj
            )
        })
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateHeadersBuildPhase() throws {
        // Given
        let target = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: target)

        let headers = Headers(
            public: ["/test/Public1.h"],
            private: ["/test/Private1.h"],
            project: ["/test/Project1.h"]
        )

        let fileElements = createFileElements(for: headers)

        // When
        try subject.generateHeadersBuildPhase(
            headers: headers,
            pbxTarget: target,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = try #require(target.buildPhases.first as? PBXHeadersBuildPhase)
        let buildFiles = buildPhase.files ?? []

        struct FileWithSettings: Equatable {
            var name: String?
            var attributes: [String]?
        }

        let buildFilesWithSettings = buildFiles.map {
            FileWithSettings(
                name: $0.file?.name,
                attributes: $0.settings?["ATTRIBUTES"]?.arrayValue
            )
        }

        #expect(buildFilesWithSettings == [
            FileWithSettings(name: "Private1.h", attributes: ["Private"]),
            FileWithSettings(name: "Public1.h", attributes: ["Public"]),
            FileWithSettings(name: "Project1.h", attributes: nil),
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateHeadersBuildPhase_empty_when_iOSAppTarget() async throws {
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let fileElements = ProjectFileElements()
        let path = try AbsolutePath(validating: "/test/file.swift")

        let sourceFileReference = PBXFileReference(sourceTree: .group, name: "Test")
        fileElements.elements[path] = sourceFileReference

        let headerPath = try AbsolutePath(validating: "/test.h")
        let headers = Headers.test(public: [path], private: [], project: [])

        let headerFileReference = PBXFileReference()
        fileElements.elements[headerPath] = headerFileReference

        let target = Target.test(
            platform: .iOS,
            sources: [SourceFile(path: "/test/file.swift", compilerFlags: nil)],
            headers: headers
        )

        let graph = Graph.test(path: tmpDir)
        let graphTraverser = GraphTraverser(graph: graph)

        try await subject.generateBuildPhases(
            path: tmpDir,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        #expect(pbxTarget.buildPhases.filter { $0 is PBXHeadersBuildPhase }.isEmpty == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateHeadersBuildPhase_before_generateSourceBuildPhase() async throws {
        let tmpDir = try #require(FileSystem.temporaryTestDirectory)
        let pbxTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        pbxproj.add(object: pbxTarget)

        let fileElements = ProjectFileElements()
        let path = try AbsolutePath(validating: "/test/file.swift")

        let sourceFileReference = PBXFileReference(sourceTree: .group, name: "Test")
        fileElements.elements[path] = sourceFileReference

        let headerPath = try AbsolutePath(validating: "/test.h")
        let headers = Headers.test(public: [path], private: [], project: [])

        let headerFileReference = PBXFileReference()
        fileElements.elements[headerPath] = headerFileReference

        let target = Target.test(
            platform: .iOS,
            product: .framework,
            sources: [SourceFile(path: "/test/file.swift", compilerFlags: nil)],
            headers: headers
        )
        let graph = Graph.test(path: tmpDir)
        let graphTraverser = GraphTraverser(graph: graph)

        try await subject.generateBuildPhases(
            path: tmpDir,
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        let firstBuildPhase: PBXBuildPhase? = pbxTarget.buildPhases.first
        #expect(firstBuildPhase != nil)
        #expect(firstBuildPhase is PBXHeadersBuildPhase == true)

        let secondBuildPhase: PBXBuildPhase? = pbxTarget.buildPhases[1]
        #expect(secondBuildPhase is PBXSourcesBuildPhase == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateResourcesBuildPhase_whenLocalizedFile() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let files: [AbsolutePath] = [
            "/path/resources/en.lproj/Main.storyboard",
            "/path/resources/en.lproj/App.strings",
            "/path/resources/fr.lproj/Main.storyboard",
            "/path/resources/fr.lproj/App.strings",
        ]

        let resources = files.map { ResourceFileElement.file(path: $0) }
        let fileElements = createLocalizedResourceFileElements(for: [
            "/path/resources/Main.storyboard",
            "/path/resources/App.strings",
        ])

        let nativeTarget = PBXNativeTarget(name: "Test")
        let pbxproj = PBXProj()
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: .test(resources: .init(resources)),
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = nativeTarget.buildPhases.first
        #expect(buildPhase?.files?.map(\.file) == [
            fileElements.elements["/path/resources/Main.storyboard"],
            fileElements.elements["/path/resources/App.strings"],
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateResourcesBuildPhase_whenLocalizedXibFiles() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let pbxproj = PBXProj()
        let fileElements = ProjectFileElements()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let files = try await TuistTest.createFiles([
            "resources/fr.lproj/Controller.strings",
            "resources/Base.lproj/Controller.xib",
            "resources/Base.lproj/Storyboard.storyboard",
            "resources/en.lproj/Controller.xib",
            "resources/en.lproj/Storyboard.strings",
            "resources/fr.lproj/Storyboard.strings",
        ])
        let groups = ProjectGroups.generate(
            project: .test(path: "/path", sourceRootPath: "/path", xcodeProjPath: "/path/Project.xcodeproj"),
            pbxproj: pbxproj
        )
        for file in files {
            try fileElements.generate(
                fileElement: GroupFileElement.folder(
                    path: file,
                    group: .group(name: "Project")
                ),
                groups: groups,
                pbxproj: pbxproj,
                sourceRootPath: path
            )
        }

        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: .test(resources: .init(files.map { .file(path: $0) })),
            graphTraverser: GraphTraverser(graph: .test(path: path)),
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = nativeTarget.buildPhases.first
        #expect(buildPhase?.files?.map(\.file?.nameOrPath) == [
            "Controller.xib",
            "Storyboard.storyboard",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateResourcesBuildPhase_whenLocalizedIntentsFile() async throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let pbxproj = PBXProj()
        let fileElements = ProjectFileElements()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let files = try await TuistTest.createFiles([
            "resources/Base.lproj/Intents.intentdefinition",
            "resources/en.lproj/Intents.strings",
            "resources/fr.lproj/Intents.strings",
        ])
        let resourceFiles = files.filter { $0.suffix != ".intentdefinition" }

        let groups = ProjectGroups.generate(
            project: .test(path: "/path", sourceRootPath: "/path", xcodeProjPath: "/path/Project.xcodeproj"),
            pbxproj: pbxproj
        )
        for file in files {
            try fileElements.generate(
                fileElement: GroupFileElement.folder(
                    path: file,
                    group: .group(name: "Project")
                ),
                groups: groups,
                pbxproj: pbxproj,
                sourceRootPath: path
            )
        }

        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: .test(resources: .init(resourceFiles.map { .file(path: $0) })),
            graphTraverser: GraphTraverser(graph: .test(path: path)),
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildFiles = try #require(nativeTarget.buildPhases.first?.files)
        #expect(buildFiles.isEmpty == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateSourcesBuildPhase_whenCoreDataModel() async throws {
        // Given
        let coreDataModel = CoreDataModel(
            path: try AbsolutePath(validating: "/Model.xcdatamodeld"),
            versions: [try AbsolutePath(validating: "/Model.xcdatamodeld/1.xcdatamodel")],
            currentVersion: "1"
        )
        let target = Target.test(resources: .init([]), coreDataModels: [coreDataModel])
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()

        let versionGroup = XCVersionGroup()
        pbxproj.add(object: versionGroup)
        fileElements.elements[try AbsolutePath(validating: "/Model.xcdatamodeld")] = versionGroup

        let model = PBXFileReference()
        pbxproj.add(object: model)
        versionGroup.children.append(model)
        fileElements.elements[try AbsolutePath(validating: "/Model.xcdatamodeld/1.xcdatamodel")] = model

        let nativeTarget = PBXNativeTarget(name: "Test")

        // When
        try await subject.generateSourcesBuildPhase(
            files: target.sources,
            coreDataModels: target.coreDataModels,
            target: target,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXSourcesBuildPhase)
        let pbxBuildFile: PBXBuildFile = try #require(pbxBuildPhase.files?.first)
        #expect(pbxBuildFile.file == versionGroup)
        #expect(versionGroup.currentVersion == model)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateResourcesBuildPhase_whenNormalResource() throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let path = try AbsolutePath(validating: "/image.png")
        let target = Target.test(resources: .init([.file(path: path)]))
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()
        let fileElement = PBXFileReference()
        pbxproj.add(object: fileElement)
        fileElements.elements[path] = fileElement

        let nativeTarget = PBXNativeTarget(name: "Test")

        let graph = Graph.test(path: temporaryPath)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        #expect(pbxBuildPhase != nil)
        #expect(pbxBuildPhase is PBXResourcesBuildPhase == true)
        let pbxBuildFile: PBXBuildFile? = pbxBuildPhase?.files?.first
        #expect(pbxBuildFile?.file == fileElement)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateResourcesBuildPhase_whenContainsResourcesTags() throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let resources: [ResourceFileElement] = [
            .file(path: "/file.type", tags: ["fileTag"]),
            .folderReference(path: "/folder", tags: ["folderTag"]),
        ]
        let target = Target.test(resources: .init(resources))
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()

        let fileElement = PBXFileReference()
        let folderElement = PBXFileReference()
        pbxproj.add(object: fileElement)
        pbxproj.add(object: folderElement)
        fileElements.elements["/file.type"] = fileElement
        fileElements.elements["/folder"] = folderElement

        let nativeTarget = PBXNativeTarget(name: "Test")

        let graph = Graph.test(path: temporaryPath)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        #expect(pbxBuildPhase != nil)
        #expect(pbxBuildPhase is PBXResourcesBuildPhase == true)

        let resourceBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXResourcesBuildPhase)
        let allFileSettings = resourceBuildPhase.files?.map(\.settings)
        #expect(allFileSettings == [
            ["ASSET_TAGS": ["fileTag"]],
            ["ASSET_TAGS": ["folderTag"]],
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateResourcesBuildPhase_whenMultiPlatformResourceFiles() throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let resources: [ResourceFileElement] = [
            .file(path: "/Shared.type"),
            .file(path: "/iOS.type", inclusionCondition: .when([.ios])),
            .file(path: "/macOS.type", inclusionCondition: .when([.macos])),
            .file(path: "/tvOS.type", inclusionCondition: .when([.tvos])),
            .file(path: "/visionOS.type", inclusionCondition: .when([.visionos])),
            .file(path: "/watchOS.type", inclusionCondition: .when([.watchos])),
        ]
        let target = Target.test(resources: .init(resources))
        let fileElements = ProjectFileElements()
        let pbxproj = PBXProj()

        for resource in resources {
            let ref = PBXFileReference()
            pbxproj.add(object: ref)
            fileElements.elements[resource.path] = ref
        }
        let nativeTarget = PBXNativeTarget(name: "Test")

        let graph = Graph.test(path: temporaryPath)
        let graphTraverser = GraphTraverser(graph: graph)
        // When
        try subject.generateResourcesBuildPhase(
            path: "/path",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let expectedPlatformFilters: [String: [String]?] = [
            "/Shared.type": nil,
            "/iOS.type": nil,
            "/macOS.type": ["macos"],
            "/tvOS.type": ["tvos"],
            "/visionOS.type": ["xros"],
            "/watchOS.type": ["watchos"],
        ]

        let pbxBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXResourcesBuildPhase)

        let resourceBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXResourcesBuildPhase)
        let buildFiles = try #require(resourceBuildPhase.files)

        for buildFile in buildFiles {
            // Explicitly exctracting the original path because it gets lost in translation for resource files
            let path = try #require(fileElements.elements.first(where: { $0.value === buildFile.file })).key

            // Actual comparison of platform filters for the given buildFile
            #expect(expectedPlatformFilters[path.pathString] == buildFile.platformFilters)
        }
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateResourceBundle() throws {
        // Given
        let path = try AbsolutePath(validating: "/path")
        let bundle1 = Target.test(name: "Bundle1", product: .bundle)
        let bundle2 = Target.test(name: "Bundle2", product: .bundle)
        let app = Target.test(name: "App", product: .app)

        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [bundle1, bundle2])

        let project = Project.test(path: path, targets: [
            bundle1,
            bundle2,
            app,
        ])

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: bundle1.name, path: project.path): Set(),
            .target(name: bundle2.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([
                .target(name: bundle1.name, path: project.path),
                .target(name: bundle2.name, path: project.path),
            ]),
        ]
        let graph = Graph.test(
            path: path,
            projects: [project.path: project],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let resourcePhase = try nativeTarget.resourcesBuildPhase()
        #expect(resourcePhase?.files?.compactMap { $0.file?.nameOrPath } == [
            "Bundle1",
            "Bundle2",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateResourceBundle_fromProjectDependency() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let bundle = Target.test(name: "Bundle1", product: .bundle)
        let app = Target.test(name: "App", product: .app)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [bundle])
        let projectA = Project.test(path: "/path/a", targets: [bundle])
        let projectB = Project.test(path: "/path/b", targets: [app])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: bundle.name, path: projectA.path): Set(),
            .target(name: app.name, path: projectB.path): Set([.target(name: bundle.name, path: projectA.path)]),
        ]

        let graph = Graph.test(
            path: path,
            projects: [projectA.path: projectA, projectB.path: projectB],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateResourcesBuildPhase(
            path: projectB.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let resourcePhase = try nativeTarget.resourcesBuildPhase()
        #expect(resourcePhase?.files?.compactMap { $0.file?.nameOrPath } == [
            "Bundle1",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateCopyFilesBuildPhases() throws {
        // Given
        let fonts: [CopyFileElement] = [
            .file(path: "/path/fonts/font1.ttf"),
            .file(path: "/path/fonts/font2.ttf"),
            .file(path: "/path/fonts/font3.ttf", condition: .when([.macos])),
            .file(path: "/path/fonts/font4.ttf", codeSignOnCopy: true),
            .file(path: "/path/fonts/font5.ttf", condition: .when([.macos]), codeSignOnCopy: true),
            .file(path: "/path/fonts/font6.ttf", codeSignOnCopy: false),
        ]

        let templates: [CopyFileElement] = [
            .file(path: "/path/sharedSupport/tuist.rtfd"),
        ]

        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createFileElements(for: (fonts + templates).map(\.path))

        let target = Target.test(copyFiles: [
            CopyFilesAction(name: "Copy Fonts", destination: .resources, subpath: "Fonts", files: fonts),
            CopyFilesAction(name: "Copy Templates", destination: .sharedSupport, subpath: "Templates", files: templates),
        ])

        // When
        try subject.generateCopyFilesBuildPhases(
            target: target,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let firstBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        #expect(firstBuildPhase.name == "Copy Fonts")
        #expect(firstBuildPhase.dstSubfolderSpec == .resources)
        #expect(firstBuildPhase.dstPath == "Fonts")
        #expect(firstBuildPhase.files?.compactMap { $0.file?.nameOrPath } == [
            "font1.ttf",
            "font2.ttf",
            "font3.ttf",
            "font4.ttf",
            "font5.ttf",
            "font6.ttf",
        ])

        #expect(firstBuildPhase.files?.map(\.platformFilters) == [
            nil,
            nil,
            ["macos"],
            nil,
            ["macos"],
            nil,
        ])

        #expect(firstBuildPhase.files?.map(\.settings) == [
            nil,
            nil,
            nil,
            ["ATTRIBUTES": ["CodeSignOnCopy"]],
            ["ATTRIBUTES": ["CodeSignOnCopy"]],
            nil,
        ])

        let secondBuildPhase = try #require(nativeTarget.buildPhases.last as? PBXCopyFilesBuildPhase)
        #expect(secondBuildPhase.name == "Copy Templates")
        #expect(secondBuildPhase.dstSubfolderSpec == .sharedSupport)
        #expect(secondBuildPhase.dstPath == "Templates")
        #expect(secondBuildPhase.files?.compactMap { $0.file?.nameOrPath } == ["tuist.rtfd"])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateAppExtensionsBuildPhase() throws {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        let appExtension = Target.test(name: "AppExtension", product: .appExtension)
        let stickerPackExtension = Target.test(name: "StickerPackExtension", product: .stickerPackExtension)
        let app = Target.test(name: "App", destinations: [.iPhone, .iPad, .mac], product: .app)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [appExtension, stickerPackExtension])
        let projectA = Project.test(path: "/path/a", targets: [
            appExtension, stickerPackExtension, app,
        ])
        let appGraphDependency: GraphDependency = .target(name: app.name, path: projectA.path)
        let stickerPackGraphDependency: GraphDependency = .target(name: stickerPackExtension.name, path: projectA.path)
        let appExtensionGraphDependency: GraphDependency = .target(name: appExtension.name, path: projectA.path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appExtensionGraphDependency: Set(),
            stickerPackGraphDependency: Set(),
            appGraphDependency: Set([
                appExtensionGraphDependency,
                stickerPackGraphDependency,
            ]),
        ]
        let dependencyConditions: [GraphEdge: PlatformCondition] = [
            .init(from: appGraphDependency, to: stickerPackGraphDependency): .when([.ios])!,
        ]

        let graph = Graph.test(
            path: path,
            projects: [projectA.path: projectA],
            dependencies: dependencies,
            dependencyConditions: dependencyConditions
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateAppExtensionsBuildPhase(
            path: projectA.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase: PBXBuildPhase? = nativeTarget.buildPhases.first
        #expect(pbxBuildPhase != nil)
        #expect(pbxBuildPhase is PBXCopyFilesBuildPhase == true)
        #expect(pbxBuildPhase?.files?.compactMap { $0.file?.nameOrPath } == [
            "AppExtension",
            "StickerPackExtension",
        ])
        #expect(pbxBuildPhase?.files?.map(\.platformFilter) == [
            nil,
            "ios",
        ])
        #expect(
            pbxBuildPhase?.files?.compactMap(\.settings) ==
                [
                    ["ATTRIBUTES": ["RemoveHeadersOnCopy"]],
                    ["ATTRIBUTES": ["RemoveHeadersOnCopy"]],
                ]
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateAppExtensionsBuildPhase_noBuildPhase_when_appDoesntHaveAppExtensions() throws {
        // Given
        let app = Target.test(name: "App", product: .app)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = ProjectFileElements()
        let project = Project.test(targets: [app])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: app.name, path: project.path): Set(),
        ]
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateAppExtensionsBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        #expect(nativeTarget.buildPhases.isEmpty == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWatchBuildPhase() throws {
        // Given
        let app = Target.test(name: "App", destinations: [.iPad, .iPhone, .mac], product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .watch2App)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, watchApp])
        let project = Project.test(targets: [app, watchApp])
        let appGraphDependency: GraphDependency = .target(name: app.name, path: project.path)
        let watchAppGraphDependency: GraphDependency = .target(name: watchApp.name, path: project.path)
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            watchAppGraphDependency: Set(),
            appGraphDependency: Set([watchAppGraphDependency]),
        ]
        let dependencyConditions: [GraphEdge: PlatformCondition] = [
            .init(from: appGraphDependency, to: watchAppGraphDependency): .when([.ios])!,
        ]
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies,
            dependencyConditions: dependencyConditions
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateEmbedWatchBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )
        // Then
        let pbxBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        #expect(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath } == [
            "WatchApp",
        ])
        #expect(pbxBuildPhase.files?.first?.platformFilter == "ios")
        #expect(
            pbxBuildPhase.files?.compactMap(\.settings) ==
                [["ATTRIBUTES": ["RemoveHeadersOnCopy"]]]
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWatchBuildPhase_watchApplication() throws {
        // Given
        let app = Target.test(name: "App", destinations: [.iPhone, .iPad, .mac], product: .app)
        let watchApp = Target.test(name: "WatchApp", platform: .watchOS, product: .app)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, watchApp])
        let project = Project.test(targets: [app, watchApp])
        let appGraphDependency: GraphDependency = .target(name: app.name, path: project.path)
        let watchAppGraphDependency: GraphDependency = .target(name: watchApp.name, path: project.path)

        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            watchAppGraphDependency: Set(),
            appGraphDependency: Set([watchAppGraphDependency]),
        ]

        let dependencyConditions: [GraphEdge: PlatformCondition] = [
            .init(from: appGraphDependency, to: watchAppGraphDependency): .when([.ios])!,
        ]

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies,
            dependencyConditions: dependencyConditions
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateEmbedWatchBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        #expect(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath } == [
            "WatchApp",
        ])
        #expect(pbxBuildPhase.files?.first?.platformFilter == "ios")
        #expect(
            pbxBuildPhase.files?.compactMap(\.settings) ==
                [["ATTRIBUTES": ["RemoveHeadersOnCopy"]]]
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateEmbedXPCServicesBuildPhase() throws {
        // Given
        let app = Target.test(name: "App", platform: .macOS, product: .app)
        let xpcService = Target.test(name: "XPCService", platform: .macOS, product: .xpc)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, xpcService])
        let project = Project.test(targets: [app, xpcService])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: xpcService.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([.target(name: xpcService.name, path: project.path)]),
        ]
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateEmbedXPCServicesBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        #expect(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath } == [
            "XPCService",
        ])
        #expect(
            pbxBuildPhase.files?.compactMap(\.settings) ==
                [["ATTRIBUTES": ["RemoveHeadersOnCopy"]]]
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateEmbedPluginsBuildPhase() throws {
        // Given
        let app = Target.test(name: "App", platform: .macOS, product: .app)
        let embedPlugin = Target.test(name: "EmbedPlugin", platform: .macOS, product: .bundle)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, embedPlugin])
        let project = Project.test(targets: [app, embedPlugin])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: embedPlugin.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([.target(name: embedPlugin.name, path: project.path)]),
        ]
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateEmbedPluginsBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        #expect(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath } == [
            "EmbedPlugin",
        ])
        #expect(
            pbxBuildPhase.files?.compactMap(\.settings) ==
                [["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]]]
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateEmbedPluginsBuildPhase_shouldNotContainGeneratedResourceBundles() throws {
        // Given
        let app = Target.test(name: "App", platform: .macOS, product: .app)
        let generatedResourceBundle = Target.test(
            name: "Feature_Resources",
            platform: .macOS,
            product: .bundle,
            bundleId: ".generated.resources"
        )
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, generatedResourceBundle])
        let project = Project.test(targets: [app, generatedResourceBundle])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: generatedResourceBundle.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([.target(name: generatedResourceBundle.name, path: project.path)]),
        ]
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateEmbedPluginsBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        #expect(nativeTarget.buildPhases.isEmpty)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateEmbedPluginsBuildPhase_macCatalystApplication() throws {
        // Given
        let app = Target.test(name: "App", destinations: [.iPhone, .iPad, .macCatalyst])
        let embedPlugin = Target.test(name: "EmbedPlugin", platform: .macOS, product: .bundle)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, embedPlugin])
        let project = Project.test(targets: [app, embedPlugin])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: embedPlugin.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([.target(name: embedPlugin.name, path: project.path)]),
        ]
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateEmbedPluginsBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        #expect(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath } == [
            "EmbedPlugin",
        ])
        #expect(
            pbxBuildPhase.files?.compactMap(\.settings) ==
                [["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]]]
        )
        #expect(
            pbxBuildPhase.files?.compactMap(\.platformFilter) ==
                [PlatformFilter.catalyst.xcodeprojValue]
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateEmbedSystemExtensionsBuildPhase() throws {
        // Given
        let app = Target.test(name: "App", platform: .macOS, product: .app)
        let systemExtension = Target.test(name: "SystemExtension", platform: .macOS, product: .systemExtension)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, systemExtension])
        let project = Project.test(targets: [app, systemExtension])
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: systemExtension.name, path: project.path): Set(),
            .target(name: app.name, path: project.path): Set([.target(name: systemExtension.name, path: project.path)]),
        ]
        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateEmbedSystemExtensionBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase = try #require(nativeTarget.buildPhases.first as? PBXCopyFilesBuildPhase)
        #expect(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath } == [
            "SystemExtension",
        ])
        #expect(
            pbxBuildPhase.files?.compactMap(\.settings) ==
                [["ATTRIBUTES": ["RemoveHeadersOnCopy"]]]
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateTarget_actions() async throws {
        // Given
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")

        let fileElements = ProjectFileElements([:])
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)
        let path = try AbsolutePath(validating: "/test")
        let pbxproj = PBXProj()
        let pbxProject = createPbxProject(pbxproj: pbxproj)
        let target = Target.test(
            sources: [],
            resources: .init([]),
            scripts: [
                TargetScript(
                    name: "post",
                    order: .post,
                    script: .scriptPath(path: path.appending(component: "script.sh"), args: ["arg"]),
                    showEnvVarsInLog: false,
                    basedOnDependencyAnalysis: false,
                    runForInstallBuildsOnly: true
                ),
                TargetScript(
                    name: "pre",
                    order: .pre,
                    script: .scriptPath(path: path.appending(component: "script.sh"), args: ["arg"])
                ),
            ]
        )
        let project = Project.test(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let groups = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )
        try fileElements.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )

        // When
        let pbxTarget = try await TargetGenerator().generateTarget(
            target: target,
            project: project,
            pbxproj: pbxproj,
            pbxProject: pbxProject,
            projectSettings: Settings.test(),
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let preBuildPhase = try #require(pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase)
        #expect(preBuildPhase.name == "pre")
        #expect(preBuildPhase.shellPath == "/bin/sh")
        #expect(preBuildPhase.shellScript == "\"$SRCROOT\"/script.sh arg")
        #expect(preBuildPhase.showEnvVarsInLog == true)
        #expect(preBuildPhase.alwaysOutOfDate == false)
        #expect(preBuildPhase.runOnlyForDeploymentPostprocessing == false)

        let postBuildPhase = try #require(pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase)
        #expect(postBuildPhase.name == "post")
        #expect(postBuildPhase.shellPath == "/bin/sh")
        #expect(postBuildPhase.shellScript == "\"$SRCROOT\"/script.sh arg")
        #expect(postBuildPhase.showEnvVarsInLog == false)
        #expect(postBuildPhase.alwaysOutOfDate == true)
        #expect(postBuildPhase.runOnlyForDeploymentPostprocessing == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateTarget_action_custom_shell() async throws {
        // Given
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")

        let fileElements = ProjectFileElements([:])
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)
        let path = try AbsolutePath(validating: "/test")
        let pbxproj = PBXProj()
        let pbxProject = createPbxProject(pbxproj: pbxproj)
        let target = Target.test(
            sources: [],
            resources: .init([]),
            scripts: [
                TargetScript(
                    name: "post",
                    order: .post,
                    script: .scriptPath(path: path.appending(component: "script.sh"), args: ["arg"]),
                    showEnvVarsInLog: false,
                    basedOnDependencyAnalysis: false,
                    runForInstallBuildsOnly: true,
                    shellPath: "/bin/zsh" // testing custom shell
                ),
                TargetScript(
                    name: "pre",
                    order: .pre,
                    script: .scriptPath(path: path.appending(component: "script.sh"), args: ["arg"]) // leaving default shell
                ),
            ]
        )
        let project = Project.test(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let groups = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )
        try fileElements.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )

        // When
        let pbxTarget = try await TargetGenerator().generateTarget(
            target: target,
            project: project,
            pbxproj: pbxproj,
            pbxProject: pbxProject,
            projectSettings: Settings.test(),
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let preBuildPhase = try #require(pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase)
        #expect(preBuildPhase.shellPath == "/bin/sh")

        let postBuildPhase = try #require(pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase)
        #expect(postBuildPhase.shellPath == "/bin/zsh")
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateTarget_action_dependency_file() async throws {
        // Given
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")

        let fileElements = ProjectFileElements([:])
        let graph = Graph.test()
        let graphTraverser = GraphTraverser(graph: graph)
        let path = try AbsolutePath(validating: "/")
        let pbxproj = PBXProj()
        let pbxProject = createPbxProject(pbxproj: pbxproj)
        let target = Target.test(
            sources: [],
            resources: .init([]),
            scripts: [
                TargetScript(
                    name: "post",
                    order: .post,
                    script: .embedded("echo test"),
                    showEnvVarsInLog: false,
                    basedOnDependencyAnalysis: false,
                    runForInstallBuildsOnly: true,
                    dependencyFile: "/$(TEMP_DIR)/dependency.d"
                ),
                TargetScript(
                    name: "pre",
                    order: .pre
                ),
            ]
        )
        let project = Project.test(
            path: path,
            sourceRootPath: path,
            xcodeProjPath: path.appending(component: "Project.xcodeproj"),
            targets: [target]
        )
        let groups = ProjectGroups.generate(
            project: project,
            pbxproj: pbxproj
        )
        try fileElements.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )

        // When
        let pbxTarget = try await TargetGenerator().generateTarget(
            target: target,
            project: project,
            pbxproj: pbxproj,
            pbxProject: pbxProject,
            projectSettings: Settings.test(),
            fileElements: fileElements,
            path: path,
            graphTraverser: graphTraverser
        )

        // Then
        let preBuildPhase = try #require(pbxTarget.buildPhases.first as? PBXShellScriptBuildPhase)
        #expect(preBuildPhase.dependencyFile == nil)

        let postBuildPhase = try #require(pbxTarget.buildPhases.last as? PBXShellScriptBuildPhase)
        #expect(postBuildPhase.dependencyFile == "$(TEMP_DIR)/dependency.d")
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateEmbedAppClipsBuildPhase() throws {
        // Given
        let app = Target.test(name: "App", destinations: [.iPhone, .iPad, .mac], product: .app)
        let appClip = Target.test(name: "AppClip", product: .appClip)
        let pbxproj = PBXProj()
        let nativeTarget = PBXNativeTarget(name: "Test")
        let fileElements = createProductFileElements(for: [app, appClip])
        let project = Project.test(targets: [app, appClip])
        let appGraphDependency: GraphDependency = .target(name: app.name, path: project.path)
        let appClipGraphDependency: GraphDependency = .target(name: appClip.name, path: project.path)
        let dependencies: [GraphDependency: Set<GraphDependency>] = [
            appClipGraphDependency: Set(),
            appGraphDependency: Set([appClipGraphDependency]),
        ]

        let dependencyConditions: [GraphEdge: PlatformCondition] = [
            .init(from: appGraphDependency, to: appClipGraphDependency): .when([.ios])!,
        ]

        let graph = Graph.test(
            path: project.path,
            projects: [project.path: project],
            dependencies: dependencies,
            dependencyConditions: dependencyConditions
        )
        let graphTraverser = GraphTraverser(graph: graph)
        // When
        try subject.generateEmbedAppClipsBuildPhase(
            path: project.path,
            target: app,
            graphTraverser: graphTraverser,
            pbxTarget: nativeTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let pbxBuildPhase = try #require(nativeTarget.buildPhases.first)
        #expect(pbxBuildPhase is PBXCopyFilesBuildPhase == true)
        #expect(pbxBuildPhase.files?.compactMap { $0.file?.nameOrPath } == ["AppClip"])
        #expect(pbxBuildPhase.files?.first?.platformFilter == "ios")
        #expect(
            pbxBuildPhase.files?.compactMap(\.settings) ==
                [["ATTRIBUTES": ["RemoveHeadersOnCopy"]]]
        )
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateBuildPhases_whenStaticFrameworkWithCoreDataModels() async throws {
        // Given
        let path = try AbsolutePath(validating: "/path/to/project")
        let coreDataModel = CoreDataModel(
            path: path.appending(component: "Model.xcdatamodeld"),
            versions: [
                path.appending(components: "Model.xcdatamodeld", "1.xcdatamodel"),
            ],
            currentVersion: "1"
        )
        let target = Target.test(platform: .iOS, product: .staticFramework, coreDataModels: [coreDataModel])
        let fileElements = createFileElements(for: [coreDataModel])
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: target.name)

        // When
        try await subject.generateBuildPhases(
            path: "/path/to/target",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let sourcesBuildPhase = pbxTarget.buildPhases.filter { $0 is PBXSourcesBuildPhase }.first
        let resourcesBuildPhase = pbxTarget.buildPhases.filter { $0 is PBXResourcesBuildPhase }.first
        let sourcesFiles = sourcesBuildPhase?.files?.compactMap {
            $0.file?.nameOrPath
        } ?? []
        let resourcesFiles = resourcesBuildPhase?.files?.compactMap {
            $0.file?.nameOrPath
        } ?? []
        #expect(sourcesFiles == [
            "Model.xcdatamodeld",
        ])
        #expect(resourcesFiles.isEmpty == true)
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateBuildPhases_whenBundleWithCoreDataModels() async throws {
        // Given
        let path = try AbsolutePath(validating: "/path/to/project")
        let coreDataModel = CoreDataModel(
            path: path.appending(component: "Model.xcdatamodeld"),
            versions: [
                path.appending(components: "Model.xcdatamodeld", "1.xcdatamodel"),
            ],
            currentVersion: "1"
        )
        let target = Target.test(platform: .iOS, product: .bundle, coreDataModels: [coreDataModel])
        let fileElements = createFileElements(for: [coreDataModel])
        let graph = Graph.test(path: path)
        let graphTraverser = GraphTraverser(graph: graph)
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: target.name)

        // When
        try await subject.generateBuildPhases(
            path: "/path/to/target",
            target: target,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let sourcesBuildPhase = pbxTarget.buildPhases.filter { $0 is PBXSourcesBuildPhase }.first
        let resourcesBuildPhase = pbxTarget.buildPhases.filter { $0 is PBXResourcesBuildPhase }.first
        let sourcesFiles = sourcesBuildPhase?.files?.compactMap {
            $0.file?.nameOrPath
        } ?? []
        let resourcesFiles = resourcesBuildPhase?.files?.compactMap {
            $0.file?.nameOrPath
        } ?? []

        #expect(sourcesFiles.isEmpty == true)
        #expect(resourcesFiles == [
            "Model.xcdatamodeld",
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateLinks_generatesAShellScriptBuildPhase_when_targetIsAMacroFramework() async throws {
        // Given
        let app = Target.test(name: "app", platform: .iOS, product: .app)
        let macroFramework = Target.test(name: "framework", platform: .iOS, product: .staticFramework)
        let macroExecutable = Target.test(name: "macro", platform: .macOS, product: .macro)
        let project = Project.test(targets: [app, macroFramework, macroExecutable])
        let fileElements = createProductFileElements(for: [app, macroFramework, macroExecutable])
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: app.name)

        let graph = Graph.test(path: project.path, projects: [project.path: project], dependencies: [
            .target(name: app.name, path: project.path): Set([.target(name: macroFramework.name, path: project.path)]),
            .target(name: macroFramework.name, path: project.path): Set([.target(
                name: macroExecutable.name,
                path: project.path
            )]),
            .target(name: macroExecutable.name, path: project.path): Set([]),
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateBuildPhases(
            path: "/Project",
            target: macroFramework,
            graphTraverser: graphTraverser,
            pbxTarget: pbxTarget,
            fileElements: fileElements,
            pbxproj: pbxproj
        )

        // Then
        let buildPhase = pbxTarget
            .buildPhases
            .compactMap { $0 as? PBXShellScriptBuildPhase }
            .first(where: { $0.name() == "Copy Swift Macro executable into $BUILT_PRODUCT_DIR" })

        #expect(buildPhase != nil)

        let expectedScript =
            "if [[ -f \"$BUILD_DIR/$CONFIGURATION/macro\" && ! -f \"$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME/macro\" ]]; then\n    mkdir -p \"$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME/\"\n    cp \"$BUILD_DIR/$CONFIGURATION/macro\" \"$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME/macro\"\nfi"
        #expect(buildPhase?.shellScript?.contains(expectedScript) == true)
        #expect(buildPhase?.inputPaths.contains("$BUILD_DIR/$CONFIGURATION/\(macroExecutable.productName)") == true)
        #expect(
            buildPhase?.outputPaths ==
                [
                    "$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME/\(macroExecutable.productName)",
                    "$BUILD_DIR/Debug-$EFFECTIVE_PLATFORM_NAME/\(macroExecutable.productName)",
                ]
        )
    }

    // MARK: - Helpers

    private func createProductFileElements(for targets: [Target]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        fileElements.products = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.name, PBXFileReference(name: $0.name))
        })
        return fileElements
    }

    private func createLocalizedResourceFileElements(for files: [AbsolutePath]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        fileElements.elements = Dictionary(uniqueKeysWithValues: files.map {
            ($0, PBXVariantGroup())
        })
        return fileElements
    }

    private func createFileElements(for files: [AbsolutePath]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        fileElements.elements = Dictionary(uniqueKeysWithValues: files.map {
            ($0, PBXFileReference(sourceTree: .group, name: $0.basename))
        })
        return fileElements
    }

    private func createFileElements(for coreDataModels: [CoreDataModel]) -> ProjectFileElements {
        let fileElements = ProjectFileElements()
        for model in coreDataModels {
            let versionGroup = XCVersionGroup(path: model.path.basename, name: model.path.basename)
            fileElements.elements[model.path] = versionGroup
            for version in model.versions {
                let fileReference = PBXFileReference(name: version.basename, path: version.basename)
                fileElements.elements[version] = fileReference
            }
        }
        return fileElements
    }

    private func createFileElements(for headers: Headers) -> ProjectFileElements {
        createFileElements(for: headers.public + headers.private + headers.project)
    }

    private func createPbxProject(pbxproj: PBXProj) -> PBXProject {
        let configList = XCConfigurationList(buildConfigurations: [])
        pbxproj.add(object: configList)
        let mainGroup = PBXGroup()
        pbxproj.add(object: mainGroup)
        let pbxProject = PBXProject(
            name: "Project",
            buildConfigurationList: configList,
            compatibilityVersion: "0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup
        )
        pbxproj.add(object: pbxProject)
        return pbxProject
    }
}
