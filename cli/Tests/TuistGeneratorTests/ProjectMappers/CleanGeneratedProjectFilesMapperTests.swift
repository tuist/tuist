import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistGenerator

struct CleanGeneratedProjectFilesMapperTests {
    private let fileSystem = FileSystem()
    private let oldDate = Date(timeIntervalSince1970: 1)

    @Test(.inTemporaryDirectory) func regeneration_preservesUnchangedGeneratedFiles() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let project = try await makeProject(at: directory)
        let files = try await generate(project)
        #expect(files.count == 4)
        for file in files {
            try setOldModificationDate(at: file)
        }

        let regeneratedFiles = try await generate(project)

        #expect(Set(regeneratedFiles) == Set(files))
        for file in files {
            #expect(try modificationDate(at: file) == oldDate)
        }
    }

    @Test(.inTemporaryDirectory) func regeneration_updatesChangedGeneratedContents() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        var project = try await makeProject(at: directory)
        let files = try await generate(project)
        for file in files {
            try setOldModificationDate(at: file)
        }
        try await fileSystem.writeText("let changed = true", at: directory.appending(component: "Custom.stencil"))
        project.targets["App"]?.infoPlist = .dictionary(["Changed": true])
        project.targets["App"]?.entitlements = .dictionary(["Changed": true])

        try await generate(project)

        let accessor = directory.appending(components: "Derived", "Sources", "TuistCustom+App.swift")
        #expect(try await fileSystem.readTextFile(at: accessor) == "let changed = true")
        for file in files where file.basename != "TuistBundle+App.swift" {
            #expect(try modificationDate(at: file) > oldDate)
        }
        let bundleAccessor = directory.appending(components: "Derived", "Sources", "TuistBundle+App.swift")
        #expect(try modificationDate(at: bundleAccessor) == oldDate)
    }

    @Test(.inTemporaryDirectory) func regeneration_removesFilesWhenTargetIsRemoved() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        var project = try await makeProject(at: directory)
        let files = try await generate(project)
        project.targets = [:]

        try await generate(project)

        for file in files {
            #expect(try await !fileSystem.exists(file))
        }
    }

    @Test(.inTemporaryDirectory) func regeneration_removesFilesWhenSynthesisIsDisabled() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        var project = try await makeProject(at: directory)
        let files = try await generate(project)
        project.options = .test(disableBundleAccessors: true, disableSynthesizedResourceAccessors: true)
        project.targets["App"]?.infoPlist = nil
        project.targets["App"]?.entitlements = nil

        try await generate(project)

        for file in files {
            #expect(try await !fileSystem.exists(file))
        }
    }

    @Test(.inTemporaryDirectory) func regeneration_removesAccessorsWhenResourcesAreRemoved() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        var project = try await makeProject(at: directory)
        let files = try await generate(project)
        project.targets["App"]?.resources = .init([])

        try await generate(project)

        for file in files {
            #expect(try await fileSystem.exists(file) == (file.extension != "swift"))
        }
    }

    @Test(.inTemporaryDirectory) func cleanup_preservesUnrelatedAndExplicitlyReferencedFiles() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        var project = try await makeProject(at: directory)
        try await generate(project)
        let sources = directory.appending(components: "Derived", "Sources")
        let unrelated = sources.appending(component: "Custom.swift")
        let referenced = sources.appending(component: "TuistCustom+Manual.swift")
        try await fileSystem.writeText("let custom = true", at: unrelated)
        try await fileSystem.writeText("let manual = true", at: referenced)
        project.targets["App"]?.sources.append(SourceFile(path: referenced))

        try await generate(project)

        #expect(try await fileSystem.readTextFile(at: unrelated) == "let custom = true")
        #expect(try await fileSystem.readTextFile(at: referenced) == "let manual = true")
    }

    private func makeProject(at directory: AbsolutePath) async throws -> Project {
        let source = directory.appending(component: "App.swift")
        let resource = directory.appending(component: "Localizable.strings")
        let template = directory.appending(component: "Custom.stencil")
        try await fileSystem.writeText("struct App {}", at: source)
        try await fileSystem.writeText("\"hello\" = \"Hello\";", at: resource)
        try await fileSystem.writeText("let greeting = \"Hello\"", at: template)
        return Project.test(
            path: directory,
            targets: [.test(
                name: "App",
                infoPlist: .dictionary(["Original": true]),
                entitlements: .dictionary(["Original": true]),
                sources: [SourceFile(path: source)],
                resources: .init([.file(path: resource)])
            )],
            resourceSynthesizers: [.init(
                parser: .strings,
                parserOptions: [:],
                extensions: ["strings"],
                template: .file(template)
            )]
        )
    }

    @discardableResult
    private func generate(_ project: Project) async throws -> [AbsolutePath] {
        let mapper = SequentialProjectMapper(mappers: [
            DeleteDerivedDirectoryProjectMapper(),
            SynthesizedResourceInterfaceProjectMapper(contentHasher: ContentHasher()),
            ResourcesProjectMapper(contentHasher: ContentHasher()),
            GenerateInfoPlistProjectMapper(),
            GenerateEntitlementsProjectMapper(),
            CleanGeneratedProjectFilesMapper(),
        ])
        let (_, sideEffects) = try await mapper.map(project: project)
        try await SideEffectDescriptorExecutor().execute(sideEffects: sideEffects)
        return sideEffects.compactMap { sideEffect in
            guard case let .file(file) = sideEffect, file.state == .present else { return nil }
            return file.path
        }
    }

    private func setOldModificationDate(at path: AbsolutePath) throws {
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: path.pathString)
    }

    private func modificationDate(at path: AbsolutePath) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.pathString)
        return try #require(attributes[.modificationDate] as? Date)
    }
}
