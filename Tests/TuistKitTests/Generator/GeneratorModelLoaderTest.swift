import Basic
import Foundation
import XCTest
@testable import ProjectDescription
@testable import TuistCoreTesting
@testable import TuistKit

class GeneratorModelLoaderTest: XCTestCase {
    typealias WorkspaceManifest = ProjectDescription.Workspace
    typealias ProjectManifest = ProjectDescription.Project
    typealias TargetManifest = ProjectDescription.Target
    typealias SettingsManifest = ProjectDescription.Settings
    typealias ConfigurationManifest = ProjectDescription.Configuration
    typealias HeadersManifest = ProjectDescription.Headers
    typealias SchemeManifest = ProjectDescription.Scheme
    typealias BuildActionManifest = ProjectDescription.BuildAction
    typealias TestActionManifest = ProjectDescription.TestAction
    typealias RunActionManifest = ProjectDescription.RunAction
    typealias ArgumentsManifest = ProjectDescription.Arguments
    typealias BuildConfigurationManifest = ProjectDescription.BuildConfiguration

    var manifestTargetGenerator: MockManifestTargetGenerator!
    var fileHandler: MockFileHandler!
    var path: AbsolutePath {
        return fileHandler.currentPath
    }

    var printer: MockPrinter!

    override func setUp() {
        do {
            printer = MockPrinter()
            fileHandler = try MockFileHandler()
            manifestTargetGenerator = MockManifestTargetGenerator()
        } catch {
            XCTFail("setup failed: \(error.localizedDescription)")
        }
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_loadProject() throws {
        // Given

        let manifests = [
            path: ProjectManifest.test(name: "SomeProject"),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator)

        // When
        let model = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(model.name, "SomeProject")
        XCTAssertEqual(model.targets.map { $0.name }, ["SomeProject-Manifest"])
    }

    func test_loadProject_withTargets() throws {
        // Given
        let targetA = TargetManifest.test(name: "A")
        let targetB = TargetManifest.test(name: "B")
        let manifests = [
            path: ProjectManifest.test(name: "Project",
                                       targets: [
                                           targetA,
                                           targetB,
                                       ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator)

        // When
        let model = try subject.loadProject(at: path)

        // Then
        XCTAssertEqual(model.targets.count, 3)
        assert(target: model.targets[0], matches: targetA, at: path)
        assert(target: model.targets[1], matches: targetB, at: path)
        XCTAssertEqual(model.targets[2].name, "Project-Manifest")
    }

    func test_loadWorkspace() throws {
        // Given
        let manifests = [
            path: WorkspaceManifest.test(name: "SomeWorkspace"),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator)

        // When
        let model = try subject.loadWorkspace(at: path)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.projects, [])
    }

    func test_loadWorkspace_withProjects() throws {
        // Given
        let path = fileHandler.currentPath
        let projects = try createFolders([
            "A",
            "B",
        ])

        let manifests = [
            path: WorkspaceManifest.test(name: "SomeWorkspace", projects: ["A", "B"]),
        ]

        let manifestLoader = createManifestLoader(with: manifests, projects: projects)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator)

        // When
        let model = try subject.loadWorkspace(at: path)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.projects, projects)
    }

    func test_loadWorkspace_withAdditionalFiles() throws {
        let path = fileHandler.currentPath
        let files = try createFiles([
            "Documentation/README.md",
            "Documentation/setup/README.md",
            "Playground.playground",
        ])

        let manifests = [
            path: WorkspaceManifest.test(name: "SomeWorkspace",
                                         projects: [],
                                         additionalFiles: [
                                             "Documentation/**/*.md",
                                             "*.playground",
                                         ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator)

        // When
        let model = try subject.loadWorkspace(at: path)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.additionalFiles, files.map { .file(path: $0) })
    }

    func test_loadWorkspace_withFolderReferences() throws {
        let path = fileHandler.currentPath
        try createFiles([
            "Documentation/README.md",
            "Documentation/setup/README.md",
        ])

        let manifests = [
            path: WorkspaceManifest.test(name: "SomeWorkspace",
                                         projects: [],
                                         additionalFiles: [
                                             .folderReference(path: "Documentation"),
                                         ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator)

        // When
        let model = try subject.loadWorkspace(at: path)

        // Then
        XCTAssertEqual(model.name, "SomeWorkspace")
        XCTAssertEqual(model.additionalFiles, [
            .folderReference(path: path.appending(RelativePath("Documentation"))),
        ])
    }

    func test_loadWorkspace_withInvalidProjectsPaths() throws {
        // Given
        let path = fileHandler.currentPath

        let manifests = [
            path: WorkspaceManifest.test(name: "SomeWorkspace", projects: ["A", "B"]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator,
                                           printer: printer)

        // When
        let model = try subject.loadWorkspace(at: path)

        // Then
        XCTAssertEqual(printer.printWarningArgs, [
            "No projects found at: A",
            "No projects found at: B",
        ])
        XCTAssertEqual(model.projects, [])
    }

    func test_loadWorkspace_withInvalidFilePaths() throws {
        // Given
        let path = fileHandler.currentPath
        try createFolders([
            "Documentation",
        ])

        let manifests = [
            path: WorkspaceManifest.test(name: "SomeWorkspace",
                                         projects: [],
                                         additionalFiles: [
                                             "Documentation/**/*.md",
                                         ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator,
                                           printer: printer)

        // When
        let model = try subject.loadWorkspace(at: path)

        // Then
        XCTAssertEqual(printer.printWarningArgs, [
            "No files found at: Documentation/**/*.md",
        ])
        XCTAssertEqual(model.additionalFiles, [])
    }

    func test_loadWorkspace_withInvalidFolderReferencePaths() throws {
        // Given
        let path = fileHandler.currentPath
        try createFiles([
            "README.md",
        ])

        let manifests = [
            path: WorkspaceManifest.test(name: "SomeWorkspace",
                                         projects: [],
                                         additionalFiles: [
                                             .folderReference(path: "Documentation"),
                                             .folderReference(path: "README.md"),
                                         ]),
        ]

        let manifestLoader = createManifestLoader(with: manifests)
        let subject = GeneratorModelLoader(fileHandler: fileHandler,
                                           manifestLoader: manifestLoader,
                                           manifestTargetGenerator: manifestTargetGenerator,
                                           printer: printer)

        // When
        let model = try subject.loadWorkspace(at: path)

        // Then
        XCTAssertEqual(printer.printWarningArgs, [
            "Documentation does not exist",
            "README.md is not a directory - folder reference paths need to point to directories",
        ])
        XCTAssertEqual(model.additionalFiles, [])
    }

    func test_settings() throws {
        // Given
        let debug = ConfigurationManifest(settings: ["Debug": "Debug"], xcconfig: "debug.xcconfig")
        let release = ConfigurationManifest(settings: ["Release": "Release"], xcconfig: "release.xcconfig")
        let manifest = SettingsManifest(base: ["base": "base"], debug: debug, release: release)

        // When
        let model = TuistKit.Settings.from(manifest: manifest, path: path)

        // Then
        assert(settings: model, matches: manifest, at: path)
    }

    func test_headers() throws {
        // Given
        let publicPath = path.appending(component: "public")
        try fileHandler.createFolder(publicPath)
        try fileHandler.touch(publicPath.appending(component: "a.h"))
        try fileHandler.touch(publicPath.appending(component: "b.h"))

        let projectPath = path.appending(component: "project")
        try fileHandler.createFolder(projectPath)
        try fileHandler.touch(projectPath.appending(component: "c.h"))

        let privatePath = path.appending(component: "private")
        try fileHandler.createFolder(privatePath)

        let manifest = HeadersManifest(public: "public/*.h", private: "private/*.h", project: "project/*.h")

        // When
        let model = TuistKit.Headers.from(manifest: manifest, path: path, fileHandler: fileHandler)

        // Then
        XCTAssertEqual(model.public, [
            publicPath.appending(component: "a.h"),
            publicPath.appending(component: "b.h"),
        ])

        XCTAssertEqual(model.project, [
            projectPath.appending(component: "c.h"),
        ])

        XCTAssertEqual(model.private, [])
    }

    func test_coreDataModel() throws {
        // Given
        try fileHandler.touch(path.appending(component: "model.xcdatamodeld"))
        let manifest = ProjectDescription.CoreDataModel("model.xcdatamodeld",
                                                        currentVersion: "1")

        // When
        let model = try TuistKit.CoreDataModel.from(manifest: manifest, path: path, fileHandler: fileHandler)

        // Then
        XCTAssertTrue(coreDataModel(model, matches: manifest, at: path))
    }

    func test_targetActions() throws {
        // Given
        let manifest = ProjectDescription.TargetAction.test(name: "MyScript",
                                                            tool: "my_tool",
                                                            path: "my/path",
                                                            order: .pre,
                                                            arguments: ["arg1", "arg2"])
        // When
        let model = TuistKit.TargetAction.from(manifest: manifest, path: path)

        // Then
        XCTAssertEqual(model.name, "MyScript")
        XCTAssertEqual(model.tool, "my_tool")
        XCTAssertEqual(model.path, path.appending(RelativePath("my/path")))
        XCTAssertEqual(model.order, .pre)
        XCTAssertEqual(model.arguments, ["arg1", "arg2"])
    }

    func test_scheme_withoutActions() throws {
        // Given
        let manifest = SchemeManifest.test(name: "Scheme",
                                           shared: false)
        // When
        let model = TuistKit.Scheme.from(manifest: manifest)

        // Then
        assert(scheme: model, matches: manifest)
    }

    func test_scheme_withActions() throws {
        // Given
        let arguments = ArgumentsManifest.test(environment: ["FOO": "BAR", "FIZ": "BUZZ"],
                                               launch: ["--help": true,
                                                        "subcommand": false])
        let buildAction = BuildActionManifest.test(targets: ["A", "B"])
        let runActions = RunActionManifest.test(config: .release,
                                                executable: "A",
                                                arguments: arguments)
        let testAction = TestActionManifest.test(targets: ["B"],
                                                 arguments: arguments,
                                                 config: .debug,
                                                 coverage: true)
        let manifest = SchemeManifest.test(name: "Scheme",
                                           shared: true,
                                           buildAction: buildAction,
                                           testAction: testAction,
                                           runAction: runActions)
        // When
        let model = TuistKit.Scheme.from(manifest: manifest)

        // Then
        assert(scheme: model, matches: manifest)
    }

    func test_platform_watchOSNotSupported() {
        XCTAssertThrowsError(
            try TuistKit.Platform.from(manifest: .watchOS)
        ) { error in
            XCTAssertEqual(error as? GeneratorModelLoaderError, GeneratorModelLoaderError.featureNotYetSupported("watchOS platform"))
        }
    }

    func test_generatorModelLoaderError_type() {
        XCTAssertEqual(GeneratorModelLoaderError.featureNotYetSupported("").type, .abort)
    }

    func test_generatorModelLoaderError_description() {
        XCTAssertEqual(GeneratorModelLoaderError.featureNotYetSupported("abc").description, "abc is not yet supported")
    }

    // MARK: - Helpers

    func createManifestLoader(with projects: [AbsolutePath: ProjectDescription.Project]) -> GraphManifestLoading {
        let manifestLoader = MockGraphManifestLoader()
        manifestLoader.loadProjectStub = { path in
            guard let manifest = projects[path] else {
                throw GraphLoadingError.manifestNotFound(path)
            }
            return manifest
        }
        manifestLoader.manifestsAtStub = { path in
            guard let _ = projects[path] else {
                return Set([])
            }
            return Set([.project])
        }
        return manifestLoader
    }

    func createManifestLoader(with workspaces: [AbsolutePath: ProjectDescription.Workspace],
                              projects: [AbsolutePath] = []) -> GraphManifestLoading {
        let manifestLoader = MockGraphManifestLoader()
        manifestLoader.loadWorkspaceStub = { path in
            guard let manifest = workspaces[path] else {
                throw GraphLoadingError.manifestNotFound(path)
            }
            return manifest
        }
        manifestLoader.manifestsAtStub = { path in
            projects.contains(path) ? Set([.project]) : Set([])
        }
        return manifestLoader
    }

    func assert(target: TuistKit.Target,
                matches manifest: ProjectDescription.Target,
                at path: AbsolutePath,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(target.name, manifest.name, file: file, line: line)
        XCTAssertEqual(target.bundleId, manifest.bundleId, file: file, line: line)
        XCTAssertTrue(target.platform == manifest.platform, file: file, line: line)
        XCTAssertTrue(target.product == manifest.product, file: file, line: line)
        XCTAssertEqual(target.infoPlist, path.appending(RelativePath(manifest.infoPlist)), file: file, line: line)
        XCTAssertEqual(target.entitlements, manifest.entitlements.map { path.appending(RelativePath($0)) }, file: file, line: line)
        XCTAssertEqual(target.environment, manifest.environment, file: file, line: line)
        assert(coreDataModels: target.coreDataModels, matches: manifest.coreDataModels, at: path, file: file, line: line)
        optionalAssert(target.settings, manifest.settings, file: file, line: line) {
            assert(settings: $0, matches: $1, at: path, file: file, line: line)
        }
    }

    func assert(settings: TuistKit.Settings,
                matches manifest: ProjectDescription.Settings,
                at path: AbsolutePath,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(settings.base, manifest.base, file: file, line: line)

        optionalAssert(settings.debug, manifest.debug, file: file, line: line) {
            assert(configuration: $0, matches: $1, at: path, file: file, line: line)
        }

        optionalAssert(settings.release, manifest.release, file: file, line: line) {
            assert(configuration: $0, matches: $1, at: path, file: file, line: line)
        }
    }

    func assert(configuration: TuistKit.Configuration,
                matches manifest: ProjectDescription.Configuration,
                at path: AbsolutePath,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(configuration.settings, manifest.settings, file: file, line: line)
        XCTAssertEqual(configuration.xcconfig, manifest.xcconfig.map { path.appending(RelativePath($0)) }, file: file, line: line)
    }

    func assert(coreDataModels: [TuistKit.CoreDataModel],
                matches manifests: [ProjectDescription.CoreDataModel],
                at path: AbsolutePath,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(coreDataModels.count, manifests.count, file: file, line: line)
        XCTAssertTrue(coreDataModels.elementsEqual(manifests, by: { coreDataModel($0, matches: $1, at: path) }),
                      file: file,
                      line: line)
    }

    func coreDataModel(_ coreDataModel: TuistKit.CoreDataModel,
                       matches manifest: ProjectDescription.CoreDataModel,
                       at path: AbsolutePath) -> Bool {
        return coreDataModel.path == path.appending(RelativePath(manifest.path))
            && coreDataModel.currentVersion == manifest.currentVersion
    }

    func assert(scheme: TuistKit.Scheme,
                matches manifest: ProjectDescription.Scheme,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(scheme.name, manifest.name, file: file, line: line)
        XCTAssertEqual(scheme.shared, manifest.shared, file: file, line: line)
        optionalAssert(scheme.buildAction, manifest.buildAction) {
            assert(buildAction: $0, matches: $1, file: file, line: line)
        }

        optionalAssert(scheme.testAction, manifest.testAction) {
            assert(testAction: $0, matches: $1, file: file, line: line)
        }

        optionalAssert(scheme.runAction, manifest.runAction) {
            assert(runAction: $0, matches: $1, file: file, line: line)
        }
    }

    func assert(buildAction: TuistKit.BuildAction,
                matches manifest: ProjectDescription.BuildAction,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(buildAction.targets, manifest.targets, file: file, line: line)
    }

    func assert(testAction: TuistKit.TestAction,
                matches manifest: ProjectDescription.TestAction,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(testAction.targets, manifest.targets, file: file, line: line)
        XCTAssertTrue(testAction.config == manifest.config, file: file, line: line)
        XCTAssertEqual(testAction.coverage, manifest.coverage, file: file, line: line)
        optionalAssert(testAction.arguments, manifest.arguments) {
            assert(arguments: $0, matches: $1, file: file, line: line)
        }
    }

    func assert(runAction: TuistKit.RunAction,
                matches manifest: ProjectDescription.RunAction,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(runAction.executable, manifest.executable, file: file, line: line)
        XCTAssertTrue(runAction.config == manifest.config, file: file, line: line)
        optionalAssert(runAction.arguments, manifest.arguments) {
            assert(arguments: $0, matches: $1, file: file, line: line)
        }
    }

    func assert(arguments: TuistKit.Arguments,
                matches manifest: ProjectDescription.Arguments,
                file: StaticString = #file,
                line: UInt = #line) {
        XCTAssertEqual(arguments.environment, manifest.environment, file: file, line: line)
        XCTAssertEqual(arguments.launch, manifest.launch, file: file, line: line)
    }

    func optionalAssert<A, B>(_ optionalA: A?,
                              _ optionalB: B?,
                              file: StaticString = #file,
                              line: UInt = #line,
                              compare: (A, B) -> Void) {
        switch (optionalA, optionalB) {
        case let (a?, b?):
            compare(a, b)
        case (nil, nil):
            break
        default:
            XCTFail("mismatch of optionals", file: file, line: line)
        }
    }

    @discardableResult
    func createFolders(_ folders: [String]) throws -> [AbsolutePath] {
        let paths = folders.map { fileHandler.currentPath.appending(RelativePath($0)) }
        try paths.forEach {
            try fileHandler.createFolder($0)
        }
        return paths
    }

    @discardableResult
    func createFiles(_ files: [String]) throws -> [AbsolutePath] {
        let paths = files.map { fileHandler.currentPath.appending(RelativePath($0)) }
        try paths.forEach {
            try fileHandler.touch($0)
        }
        return paths
    }
}

private func == (_ lhs: TuistKit.Platform,
                 _: ProjectDescription.Platform) -> Bool {
    let map: [TuistKit.Platform: ProjectDescription.Platform] = [
        .iOS: .iOS,
        .macOS: .macOS,
        .tvOS: .tvOS,
    ]
    return map[lhs] != nil
}

private func == (_ lhs: TuistKit.Product,
                 _: ProjectDescription.Product) -> Bool {
    let map: [TuistKit.Product: ProjectDescription.Product] = [
        .app: .app,
        .framework: .framework,
        .unitTests: .unitTests,
        .uiTests: .uiTests,
        .staticLibrary: .staticLibrary,
        .dynamicLibrary: .dynamicLibrary,
    ]
    return map[lhs] != nil
}

private func == (_ lhs: TuistKit.BuildConfiguration,
                 _: ProjectDescription.BuildConfiguration) -> Bool {
    let map: [TuistKit.BuildConfiguration: ProjectDescription.BuildConfiguration] = [
        .debug: .debug,
        .release: .release,
    ]
    return map[lhs] != nil
}

extension AbsolutePath: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
