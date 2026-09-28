import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
@testable import TuistGenerator
@testable import TuistTesting

struct SideEffectDescriptorExecutorTests {
    private let fileSystem = FileSystem()
    private let commandRunner = MockCommandRunner()
    private let subject: SideEffectDescriptorExecutor

    init() {
        subject = SideEffectDescriptorExecutor(fileSystem: fileSystem, commandRunner: commandRunner)
    }

    @Test(.inTemporaryDirectory) func execute_doesNotRewriteFileWhenContentsAreUnchanged() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "Generated.swift")
        let contents = Data("let value = 1\n".utf8)
        let oldDate = Date(timeIntervalSince1970: 1)
        try await fileSystem.writeText("let value = 1\n", at: path)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: path.pathString
        )

        try await subject.execute(sideEffects: [
            .file(FileDescriptor(path: path, contents: contents)),
        ])

        #expect(try modificationDate(at: path) == oldDate)
    }

    @Test(.inTemporaryDirectory) func execute_rewritesFileWhenContentsChange() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory).appending(component: "Generated.swift")
        let oldDate = Date(timeIntervalSince1970: 1)
        try await fileSystem.writeText("let value = 1\n", at: path)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: path.pathString
        )

        try await subject.execute(sideEffects: [
            .file(FileDescriptor(path: path, contents: Data("let value = 2\n".utf8))),
        ])

        #expect(try await fileSystem.readTextFile(at: path) == "let value = 2\n")
        #expect(try modificationDate(at: path) > oldDate)
    }

    @Test(.inTemporaryDirectory) func execute_createsSymbolicLink() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let destination = temporaryDirectory.appending(components: "Artifacts", "Module.xcframework")
        let link = temporaryDirectory.appending(components: "Derived", "FrameworkSearchPaths", "Module.xcframework")
        try await fileSystem.makeDirectory(at: destination)

        try await subject.execute(sideEffects: [
            .symbolicLink(SymbolicLinkDescriptor(path: link, destination: destination)),
        ])

        #expect(try await fileSystem.resolveSymbolicLink(link) == destination)
    }

    @Test(.inTemporaryDirectory) func execute_replacesDanglingSymbolicLink() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let oldDestination = temporaryDirectory.appending(components: "Artifacts", "old", "Module.xcframework")
        let newDestination = temporaryDirectory.appending(components: "Artifacts", "new", "Module.xcframework")
        let link = temporaryDirectory.appending(components: "Derived", "FrameworkSearchPaths", "Module.xcframework")
        try await fileSystem.makeDirectory(at: oldDestination)
        try await fileSystem.makeDirectory(at: newDestination)
        try await fileSystem.makeDirectory(at: link.parentDirectory)
        try await fileSystem.createSymbolicLink(from: link, to: oldDestination)
        try await fileSystem.remove(oldDestination)

        try await subject.execute(sideEffects: [
            .symbolicLink(SymbolicLinkDescriptor(path: link, destination: newDestination)),
        ])

        #expect(try await fileSystem.resolveSymbolicLink(link) == newDestination)
    }

    @Test(.inTemporaryDirectory) func execute_createsSymbolicLinkWithoutListingItsDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let destination = temporaryDirectory.appending(components: "Artifacts", "Module.framework")
        let directory = temporaryDirectory.appending(components: "Derived", "FrameworkSearchPaths", "Swift", "App")
        let existingLink = directory.appending(component: "Existing.framework")
        let link = directory.appending(component: "Module.framework")
        try await fileSystem.makeDirectory(at: destination)
        try await fileSystem.makeDirectory(at: directory)
        try await fileSystem.createSymbolicLink(from: existingLink, to: destination)
        // Write and search permissions only: entries can be created and looked up, but listing the directory fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: directory.pathString)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.pathString) }

        try await subject.execute(sideEffects: [
            .symbolicLink(SymbolicLinkDescriptor(path: link, destination: destination)),
        ])

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.pathString) == destination.pathString)
    }

    @Test(.inTemporaryDirectory) func execute_replacesDirectoryWithSymbolicLink() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let destination = temporaryDirectory.appending(components: "Artifacts", "Module.framework")
        let link = temporaryDirectory.appending(components: "Derived", "Module.framework")
        try await fileSystem.makeDirectory(at: destination)
        try await fileSystem.makeDirectory(at: link)

        try await subject.execute(sideEffects: [
            .symbolicLink(SymbolicLinkDescriptor(path: link, destination: destination)),
        ])

        #expect(try await fileSystem.resolveSymbolicLink(link) == destination)
        #expect(try await fileSystem.exists(destination, isDirectory: true))
    }

    @Test(.inTemporaryDirectory) func execute_removesDanglingSymbolicLink() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let destination = temporaryDirectory.appending(components: "Artifacts", "Module.framework")
        let link = temporaryDirectory.appending(components: "Derived", "Module.framework")
        try await fileSystem.makeDirectory(at: link.parentDirectory)
        try await fileSystem.createSymbolicLink(from: link, to: destination)

        try await subject.execute(sideEffects: [
            .symbolicLink(SymbolicLinkDescriptor(path: link, destination: destination, state: .absent)),
        ])

        #expect(try FileManager.default.contentsOfDirectory(atPath: link.parentDirectory.pathString).isEmpty)
    }

    @Test(.inTemporaryDirectory) func execute_createsSymbolicLinksAcrossManyDirectories() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let artifacts = temporaryDirectory.appending(component: "Artifacts")
        let staleDestination = temporaryDirectory.appending(component: "Stale.framework")
        let linksDirectory = temporaryDirectory.appending(components: "Derived", "FrameworkSearchPaths", "Swift")
        var descriptors: [SideEffectDescriptor] = []
        var expectedDestinations: [AbsolutePath: AbsolutePath] = [:]
        for frameworkIndex in 0 ..< 40 {
            try await fileSystem.makeDirectory(at: artifacts.appending(component: "Module\(frameworkIndex).framework"))
        }
        for targetIndex in 0 ..< 30 {
            let targetDirectory = linksDirectory.appending(component: "Target\(targetIndex)")
            if targetIndex.isMultiple(of: 3) {
                try await fileSystem.makeDirectory(at: targetDirectory)
                try await fileSystem.createSymbolicLink(
                    from: targetDirectory.appending(component: "Module0.framework"),
                    to: staleDestination
                )
            }
            for frameworkIndex in 0 ..< 40 {
                let destination = artifacts.appending(component: "Module\(frameworkIndex).framework")
                let link = targetDirectory.appending(component: destination.basename)
                expectedDestinations[link] = destination
                descriptors.append(.symbolicLink(SymbolicLinkDescriptor(path: link, destination: destination)))
            }
        }

        try await subject.execute(sideEffects: descriptors)

        for (link, destination) in expectedDestinations {
            #expect(try await fileSystem.resolveSymbolicLink(link) == destination)
        }
    }

    @Test(.inTemporaryDirectory) func execute_writesFilesAfterTheGeneratedFilesCleanupThatPrecedesThem() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory).appending(component: "FrameworkSearchPaths")
        let responseFiles = (0 ..< 20).map { directory.appending(component: "Target\($0).resp") }
        let links = (0 ..< 20).map { directory.appending(components: "Swift", "Target\($0)", "Module.framework") }
        let destination = try #require(FileSystem.temporaryTestDirectory).appending(component: "Module.framework")
        try await fileSystem.makeDirectory(at: destination)
        for responseFile in responseFiles {
            try await fileSystem.makeDirectory(at: responseFile.parentDirectory)
            try await fileSystem.writeText("stale", at: responseFile)
        }

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(.init(directories: [directory], activeFilesByDirectory: [:], include: ["*.resp"])),
            .generatedFilesCleanup(.init(
                directories: [directory],
                activeFilesByDirectory: [:],
                include: ["Swift/*/*.framework"]
            )),
        ] + responseFiles.map { .file(FileDescriptor(path: $0, contents: Data("active".utf8))) }
            + links.map { .symbolicLink(SymbolicLinkDescriptor(path: $0, destination: destination)) })

        for responseFile in responseFiles {
            #expect(try await fileSystem.readTextFile(at: responseFile) == "active")
        }
        for link in links {
            #expect(try await fileSystem.resolveSymbolicLink(link) == destination)
        }
    }

    @Test(.inTemporaryDirectory) func execute_keepsTheOrderOfOverlappingDescriptors() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let recreatedDirectory = temporaryDirectory.appending(component: "Recreated")
        let removedDirectory = temporaryDirectory.appending(component: "Removed")
        let rewrittenFile = temporaryDirectory.appending(component: "Rewritten.txt")
        try await fileSystem.makeDirectory(at: recreatedDirectory)
        try await fileSystem.writeText("stale", at: recreatedDirectory.appending(component: "Stale.txt"))

        try await subject.execute(sideEffects: [
            .directory(DirectoryDescriptor(path: recreatedDirectory, state: .absent)),
            .file(FileDescriptor(path: recreatedDirectory.appending(component: "File.txt"), contents: Data("new".utf8))),
            .file(FileDescriptor(path: removedDirectory.appending(component: "File.txt"), contents: Data("new".utf8))),
            .directory(DirectoryDescriptor(path: removedDirectory, state: .absent)),
            .file(FileDescriptor(path: rewrittenFile, contents: Data("first".utf8))),
            .file(FileDescriptor(path: rewrittenFile, contents: Data("second".utf8))),
        ])

        #expect(try await fileSystem.readTextFile(at: recreatedDirectory.appending(component: "File.txt")) == "new")
        #expect(try await !fileSystem.exists(recreatedDirectory.appending(component: "Stale.txt")))
        #expect(try await !fileSystem.exists(removedDirectory))
        #expect(try await fileSystem.readTextFile(at: rewrittenFile) == "second")
    }

    @Test(.inTemporaryDirectory) func execute_runsCommandsInOrder() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        commandRunner.succeedCommand(["first"])
        commandRunner.succeedCommand(["second"])

        try await subject.execute(sideEffects: [
            .command(CommandDescriptor(command: "first")),
            .file(FileDescriptor(path: temporaryDirectory.appending(component: "A.txt"))),
            .file(FileDescriptor(path: temporaryDirectory.appending(component: "B.txt"))),
            .command(CommandDescriptor(command: "second")),
        ])

        #expect(commandRunner.calls == ["first", "second"])
    }

    @Test(.inTemporaryDirectory) func execute_matchesGlobDotsLiterallyWhenCleaningGeneratedFiles() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let matchingFile = directory.appending(components: "Swift", "App", "Module.framework")
        let literalDotFile = directory.appending(components: "Swift", "App", "ModuleXframework")
        try await fileSystem.makeDirectory(at: matchingFile.parentDirectory)
        try await fileSystem.writeText("", at: matchingFile)
        try await fileSystem.writeText("", at: literalDotFile)

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(.init(
                directories: [directory],
                activeFilesByDirectory: [:],
                include: ["Swift/*/*.framework"]
            )),
        ])

        #expect(try await !fileSystem.exists(matchingFile))
        #expect(try await fileSystem.exists(literalDotFile))
    }

    @Test(.inTemporaryDirectory) func execute_cleansStaleGeneratedFiles() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory).appending(component: "ModuleMaps")
        let activeFile = directory.appending(component: "App-deps.modulemap")
        let staleFile = directory.appending(component: "Deleted-deps.modulemap")
        let preservedFile = directory.appending(component: "Package.modulemap")
        try await fileSystem.makeDirectory(at: directory)
        try await fileSystem.writeText("active", at: activeFile)
        try await fileSystem.writeText("stale", at: staleFile)
        try await fileSystem.writeText("preserved", at: preservedFile)

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(
                GeneratedFilesCleanupDescriptor(
                    directories: [directory],
                    activeFilesByDirectory: [directory: [activeFile]],
                    include: ["*-deps.modulemap"]
                )
            ),
        ])

        #expect(try await fileSystem.exists(activeFile))
        #expect(try await !fileSystem.exists(staleFile))
        #expect(try await fileSystem.exists(preservedFile))
    }

    @Test(.inTemporaryDirectory) func execute_matchesActiveFilesUsingFilesystemCaseSensitivity() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let existingFile = directory.appending(component: "App-Info.plist")
        let activeFile = directory.appending(component: "APP-Info.plist")
        let oldDate = Date(timeIntervalSince1970: 1)
        try await fileSystem.writeText("active", at: existingFile)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: existingFile.pathString)
        let refersToExistingFile = try await fileSystem.exists(activeFile)

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(.init(
                directories: [directory],
                activeFilesByDirectory: [directory: [activeFile]],
                include: ["*-Info.plist"]
            )),
        ])

        #expect(try await fileSystem.exists(existingFile) == refersToExistingFile)
        if refersToExistingFile {
            #expect(try modificationDate(at: activeFile) == oldDate)
        }
    }

    @Test(.inTemporaryDirectory) func execute_doesNotCleanThroughSymbolicLinkRoot() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let destination = temporaryDirectory.appending(component: "External")
        let externalFile = destination.appending(component: "OtherApp.entitlements")
        let link = temporaryDirectory.appending(component: "Entitlements")
        try await fileSystem.makeDirectory(at: destination)
        try await fileSystem.writeText("external contents", at: externalFile)
        try await fileSystem.createSymbolicLink(from: link, to: destination)

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(.init(
                directories: [link],
                activeFilesByDirectory: [:],
                include: ["*.entitlements"]
            )),
        ])

        #expect(try await fileSystem.readTextFile(at: externalFile) == "external contents")
        #expect(try await fileSystem.resolveSymbolicLink(link) == destination)
    }

    @Test(.inTemporaryDirectory) func execute_cleansStaleGeneratedSymbolicLinks() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = temporaryDirectory.appending(component: "FrameworkSearchPaths")
        let activeDestination = temporaryDirectory.appending(components: "Artifacts", "Active.framework")
        let staleDestination = temporaryDirectory.appending(components: "Artifacts", "Stale.framework")
        let activeLink = directory.appending(components: "Swift", "App", "Active.framework")
        let staleLink = directory.appending(components: "Swift", "Deleted", "Stale.framework")
        try await fileSystem.makeDirectory(at: activeDestination)
        try await fileSystem.makeDirectory(at: staleDestination)
        try await fileSystem.makeDirectory(at: activeLink.parentDirectory)
        try await fileSystem.makeDirectory(at: staleLink.parentDirectory)
        try await fileSystem.createSymbolicLink(from: activeLink, to: activeDestination)
        try await fileSystem.createSymbolicLink(from: staleLink, to: staleDestination)
        try await fileSystem.remove(staleDestination)

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(
                GeneratedFilesCleanupDescriptor(
                    directories: [directory],
                    activeFilesByDirectory: [directory: [activeLink]],
                    include: ["Swift/*/*.framework"]
                )
            ),
        ])

        #expect(try await fileSystem.resolveSymbolicLink(activeLink) == activeDestination)
        await #expect(throws: FileSystemError.absentSymbolicLink(staleLink)) {
            try await fileSystem.resolveSymbolicLink(staleLink)
        }
        #expect(try await !fileSystem.contentsOfDirectory(staleLink.parentDirectory).contains(staleLink))
    }

    @Test(.inTemporaryDirectory) func execute_doesNotCleanFilesInsideActiveGeneratedSymbolicLink() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let directory = temporaryDirectory.appending(component: "FrameworkSearchPaths")
        let artifact = temporaryDirectory.appending(components: "Artifacts", "Module.xcframework")
        let nestedFramework = artifact.appending(components: "ios-arm64", "Module.framework")
        let activeLink = directory.appending(components: "Swift", "App", "Module.xcframework")
        try await fileSystem.makeDirectory(at: nestedFramework)
        try await fileSystem.makeDirectory(at: activeLink.parentDirectory)
        try await fileSystem.createSymbolicLink(from: activeLink, to: artifact)

        try await subject.execute(sideEffects: [
            .generatedFilesCleanup(
                GeneratedFilesCleanupDescriptor(
                    directories: [directory],
                    activeFilesByDirectory: [directory: [activeLink]],
                    include: ["**/*.framework", "**/*.xcframework"]
                )
            ),
        ])

        #expect(try await fileSystem.resolveSymbolicLink(activeLink) == artifact)
        #expect(try await fileSystem.exists(nestedFramework, isDirectory: true))
    }

    private func modificationDate(at path: AbsolutePath) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: path.pathString)
        return try #require(attributes[.modificationDate] as? Date)
    }
}
