import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import XcodeProj
@testable import TuistGenerator

struct XcodeProjWriterXCProjTests {
    private let fileSystem = FileSystem()
    private let writer = XcodeProjWriter()
    private let pinnedDate = Date(timeIntervalSince1970: 1)

    @Test(.inTemporaryDirectory) func regeneration_preservesTargetIdentifiersAndModificationDate() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let first = try makeProject(at: directory)
        let projectPath = first.xcodeprojPath.appending(component: "project.xcproj")
        try await writer.write(project: first)
        let firstContents = try await fileSystem.readFile(at: projectPath)
        let firstTarget = try #require(first.xcodeProj.pbxproj.nativeTargets.first)
        #expect(!firstTarget.uuid.hasPrefix("TEMP_"))
        #expect(!String(decoding: firstContents, as: UTF8.self).contains("TEMP_"))
        try pinModificationDate(at: projectPath)

        let regenerated = try makeProject(at: directory)
        try await writer.write(project: regenerated)

        let regeneratedTarget = try #require(regenerated.xcodeProj.pbxproj.nativeTargets.first)
        #expect(regeneratedTarget.uuid == firstTarget.uuid)
        #expect(try await fileSystem.readFile(at: projectPath) == firstContents)
        #expect(try modificationDate(at: projectPath) == pinnedDate)
        let decoded = try XcodeProj(pathString: regenerated.xcodeprojPath.pathString)
        #expect(decoded.pbxproj.nativeTargets.first?.uuid == firstTarget.uuid)
    }

    @Test(.inTemporaryDirectory) func regeneration_rewritesChangedProject() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let first = try makeProject(at: directory)
        let projectPath = first.xcodeprojPath.appending(component: "project.xcproj")
        try await writer.write(project: first)
        let firstContents = try await fileSystem.readFile(at: projectPath)
        try pinModificationDate(at: projectPath)

        try await writer.write(project: makeProject(at: directory, targetName: "RenamedApp"))

        #expect(try await fileSystem.readFile(at: projectPath) != firstContents)
        #expect(try modificationDate(at: projectPath) != pinnedDate)
        let decoded = try XcodeProj(pathString: first.xcodeprojPath.pathString)
        #expect(decoded.pbxproj.nativeTargets.first?.name == "RenamedApp")
    }

    @Test(.inTemporaryDirectory) func regeneration_rewritesDivergentProjectFile() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let descriptor = try makeProject(at: directory)
        let projectPath = descriptor.xcodeprojPath.appending(component: "project.xcproj")
        try await writer.write(project: descriptor)
        let expectedContents = try await fileSystem.readFile(at: projectPath)
        try Data("stale".utf8).write(to: projectPath.url)
        try pinModificationDate(at: projectPath)

        try await writer.write(project: makeProject(at: directory))

        #expect(try await fileSystem.readFile(at: projectPath) == expectedContents)
        #expect(try modificationDate(at: projectPath) != pinnedDate)
    }

    @Test(.inTemporaryDirectory) func switchingFormats_removesStaleProjectBody() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let descriptor = try makeProject(at: directory)
        let xcprojPath = descriptor.xcodeprojPath.appending(component: "project.xcproj")
        let pbxprojPath = descriptor.xcodeprojPath.appending(component: "project.pbxproj")
        descriptor.xcodeProj.projectFormat = .pbxproj
        try await writer.write(project: descriptor)

        try await writer.write(project: makeProject(at: directory))

        #expect(try await fileSystem.exists(xcprojPath))
        #expect(try await !fileSystem.exists(pbxprojPath))
        descriptor.xcodeProj.projectFormat = .pbxproj
        try await writer.write(project: descriptor)
        #expect(try await fileSystem.exists(pbxprojPath))
        #expect(try await !fileSystem.exists(xcprojPath))
    }

    private func makeProject(at directory: AbsolutePath, targetName: String = "App") throws -> ProjectDescriptor {
        let descriptor = ProjectDescriptor.test(
            path: directory,
            xcodeprojPath: directory.appending(component: "Project.xcodeproj")
        )
        let project = try #require(descriptor.xcodeProj.pbxproj.rootObject)
        let target = PBXNativeTarget(name: targetName, productType: .application)
        descriptor.xcodeProj.pbxproj.add(object: target)
        project.targets = [target]
        descriptor.xcodeProj.projectFormat = .xcproj
        return descriptor
    }

    private func pinModificationDate(at path: AbsolutePath) throws {
        try FileManager.default.setAttributes([.modificationDate: pinnedDate], ofItemAtPath: path.pathString)
    }

    private func modificationDate(at path: AbsolutePath) throws -> Date {
        try #require(FileManager.default.attributesOfItem(atPath: path.pathString)[.modificationDate] as? Date)
    }
}
