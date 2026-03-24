import FileSystem
import FileSystemTesting
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistLoader
@testable import TuistTesting

struct HeadersManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory) func test_from() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles([
            "Sources/public/A1.h", "Sources/public/A1.m", "Sources/public/A2.h", "Sources/public/A2.m",
            "Sources/private/B1.h", "Sources/private/B1.m", "Sources/private/B2.h", "Sources/private/B2.m",
            "Sources/project/C1.h", "Sources/project/C1.m", "Sources/project/C2.h", "Sources/project/C2.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: "Sources/public/**",
            private: "Sources/private/**",
            project: "Sources/project/**"
        )

        // When
        let model = try await XcodeGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA",
            fileSystem: fileSystem
        )

        // Then
        #expect(model.public == (try [
            "Sources/public/A1.h", "Sources/public/A2.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))

        #expect(model.private == (try [
            "Sources/private/B1.h", "Sources/private/B2.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))

        #expect(model.project == (try [
            "Sources/project/C1.h", "Sources/project/C2.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func from_when_array() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles([
            "Sources/public/A/A1.h", "Sources/public/A/A1.m", "Sources/public/B/B1.h", "Sources/public/B/B1.m",
            "Sources/private/C/C1.h", "Sources/private/C/C1.m", "Sources/private/D/D1.h", "Sources/private/D/D1.m",
            "Sources/project/E/E1.h", "Sources/project/E/E1.m", "Sources/project/F/F1.h", "Sources/project/F/F1.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: ["Sources/public/A/*.h", "Sources/public/B/*.h"],
            private: ["Sources/private/C/*.h", "Sources/private/D/*.h"],
            project: ["Sources/project/E/*.h", "Sources/project/F/*.h"]
        )

        // When
        let model = try await XcodeGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA",
            fileSystem: fileSystem
        )

        // Then
        #expect(model.public == (try [
            "Sources/public/A/A1.h", "Sources/public/B/B1.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))

        #expect(model.private == (try [
            "Sources/private/C/C1.h", "Sources/private/D/D1.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))

        #expect(model.project == (try [
            "Sources/project/E/E1.h", "Sources/project/F/F1.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func from_when_array_and_string() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles([
            "Sources/public/A/A1.h", "Sources/public/A/A1.m",
            "Sources/project/C/C1.h", "Sources/project/C/C1.m",
            "Sources/project/D/D1.h", "Sources/project/D/D1.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: "Sources/public/A/*.h",
            project: ["Sources/project/C/*.h", "Sources/project/D/*.h"]
        )

        // When
        let model = try await XcodeGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA",
            fileSystem: fileSystem
        )

        // Then
        #expect(model.public == (try [
            "Sources/public/A/A1.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))

        #expect(model.project == (try [
            "Sources/project/C/C1.h", "Sources/project/D/D1.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func from_and_excluding() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: temporaryPath,
            rootDirectory: temporaryPath
        )
        try await TuistTest.createFiles([
            "Sources/public/A1.h", "Sources/public/A1.m", "Sources/public/A2.h", "Sources/public/A2.m",
            "Sources/private/B1.h", "Sources/private/B1.m", "Sources/private/B2.h", "Sources/private/B2.m",
            "Sources/project/C1.h", "Sources/project/C1.m", "Sources/project/C2.h", "Sources/project/C2.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: .list([.glob("Sources/public/**", excluding: "Sources/public/A2.h")]),
            private: .list([.glob("Sources/private/**", excluding: "Sources/private/B1.h")]),
            project: "Sources/project/**"
        )

        // When
        let model = try await XcodeGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA",
            fileSystem: fileSystem
        )

        // Then
        #expect(model.public == (try [
            "Sources/public/A1.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))

        #expect(model.private == (try [
            "Sources/private/B2.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))

        #expect(model.project == (try [
            "Sources/project/C1.h", "Sources/project/C2.h",
        ].map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func from_and_excluding_same_folder() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await TuistTest.createFiles([
            "Sources/A1.h", "Sources/A1.m", "Sources/A2.h", "Sources/A2.m",
            "Sources/A1+Project.h", "Sources/A1+Project.m", "Sources/A2+Protected.h", "Sources/A2+Protected.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: .list([.glob("Sources/**", excluding: ["Sources/*+Protected.h", "Sources/*+Project.h"])]),
            private: nil,
            project: ["Sources/*+Protected.h", "Sources/*+Project.h"]
        )

        let model = try await XcodeGraph.Headers.from(
            manifest: manifest, generatorPaths: generatorPaths, productName: "ModuleA", fileSystem: fileSystem
        )

        #expect(model.public == (try ["Sources/A1.h", "Sources/A2.h"]
                .map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.private == [])
        #expect(model.project.sorted() == (try ["Sources/A1+Project.h", "Sources/A2+Protected.h"]
                .sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func from_and_excluding_in_nested_folder() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await TuistTest.createFiles([
            "Sources/group/A1.h", "Sources/group/A1.m", "Sources/group/A2.h", "Sources/group/A2.m",
            "Sources/group/A1+Project.h", "Sources/group/A1+Project.m",
            "Sources/group/A2+Protected.h", "Sources/group/A2+Protected.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: .list([.glob("Sources/**", excluding: ["Sources/**/*+Protected.h", "Sources/**/*+Project.h"])]),
            private: nil,
            project: ["Sources/**/*+Protected.h", "Sources/**/*+Project.h"]
        )

        let model = try await XcodeGraph.Headers.from(
            manifest: manifest, generatorPaths: generatorPaths, productName: "ModuleA", fileSystem: fileSystem
        )

        #expect(model.public == (try ["Sources/group/A1.h", "Sources/group/A2.h"]
                .map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.private == [])
        #expect(model.project.sorted() == (try ["Sources/group/A1+Project.h", "Sources/group/A2+Protected.h"]
                .sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func exclusionRule_projectExcludesPrivateAndPublic() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await TuistTest.createFiles([
            "Sources/group/A1.h", "Sources/group/A1.m", "Sources/group/A1+Project.h", "Sources/group/A1+Project.m",
            "Sources/group/A2.h", "Sources/group/A2.m", "Sources/group/A2+Protected.h", "Sources/group/A2+Protected.m",
            "Sources/group/A3.h", "Sources/group/A3.m", "Sources/group/A4+Private.h", "Sources/group/A4+Private.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: .list([.glob("Sources/**", excluding: [
                "Sources/**/*+Protected.h", "Sources/**/*+Project.h", "Sources/**/*+Private.h",
            ])]),
            private: ["Sources/**/*+Private.h"],
            project: ["Sources/**"],
            exclusionRule: .projectExcludesPrivateAndPublic
        )

        let model = try await XcodeGraph.Headers.from(
            manifest: manifest, generatorPaths: generatorPaths, productName: "ModuleA", fileSystem: fileSystem
        )

        #expect(model.public == (try ["Sources/group/A1.h", "Sources/group/A2.h", "Sources/group/A3.h"]
                .map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.private == (try ["Sources/group/A4+Private.h"]
                .map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.project.sorted() == (try ["Sources/group/A1+Project.h", "Sources/group/A2+Protected.h"]
                .sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func exclusionRule_publicExcludesPrivateAndProject() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)
        try await TuistTest.createFiles([
            "Sources/group/A1.h", "Sources/group/A1.m", "Sources/group/A1+Project.h", "Sources/group/A1+Project.m",
            "Sources/group/A2.h", "Sources/group/A2.m", "Sources/group/A2+Protected.h", "Sources/group/A2+Protected.m",
            "Sources/group/A3.h", "Sources/group/A3.m", "Sources/group/A4+Private.h", "Sources/group/A4+Private.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: ["Sources/**"],
            private: ["Sources/**/*+Private.h"],
            project: ["Sources/**/*+Protected.h", "Sources/**/*+Project.h"],
            exclusionRule: .publicExcludesPrivateAndProject
        )

        let model = try await XcodeGraph.Headers.from(
            manifest: manifest, generatorPaths: generatorPaths, productName: "ModuleA", fileSystem: fileSystem
        )

        #expect(model.public == (try ["Sources/group/A1.h", "Sources/group/A2.h", "Sources/group/A3.h"]
                .map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.private == (try ["Sources/group/A4+Private.h"]
                .map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.project.sorted() == (try ["Sources/group/A1+Project.h", "Sources/group/A2+Protected.h"]
                .sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func load_from_umbrella() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)

        let umbrellaContent = """
        #import <Foundation/Foundation.h>
        FOUNDATION_EXPORT double TuistTestModuleVersionNumber;
        FOUNDATION_EXPORT const unsigned char TuistTestModuleVersionString[];
        #import <TuistTestModule/A1.h>
          #import <TuistTestModule/A2.h>
        #import "A3.h"
        #import <TuistTestModule/A2+Protected.h>
        #import <UIKit/A4+Private.h>
        """
        let umbrellaPath = temporaryPath.appending(try RelativePath(validating: "Sources/Umbrella.h"))

        try await TuistTest.createFiles([
            "Sources/group/A1.h", "Sources/group/A2.h", "Sources/group/A3.h",
            "Sources/group/A1+Project.h", "Sources/group/A2+Protected.h", "Sources/group/A4+Private.h",
        ])
        try createVersionFile(content: umbrellaContent, in: umbrellaPath)

        let manifest = ProjectDescription.Headers.allHeaders(from: "Sources/**", umbrella: "Sources/Umbrella.h")

        let model = try await XcodeGraph.Headers.from(
            manifest: manifest, generatorPaths: generatorPaths, productName: "TuistTestModule", fileSystem: fileSystem
        )

        #expect(model.public.sorted() == (try [
            "Sources/Umbrella.h", "Sources/group/A1.h", "Sources/group/A2.h",
            "Sources/group/A3.h", "Sources/group/A2+Protected.h",
        ].sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.private == [])
        #expect(model.project.sorted() == (try [
            "Sources/group/A1+Project.h", "Sources/group/A4+Private.h",
        ].sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func load_from_umbrella_withExcluding() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)

        let umbrellaContent = """
        #import <Foundation/Foundation.h>
        FOUNDATION_EXPORT double TuistTestModuleVersionNumber;
        FOUNDATION_EXPORT const unsigned char TuistTestModuleVersionString[];
        #import <TuistTestModule/A1.h>
          #import <TuistTestModule/A2.h>
        #import "A3.h"
        """
        let umbrellaPath = temporaryPath.appending(try RelativePath(validating: "Sources/Umbrella.h"))

        try await TuistTest.createFiles([
            "Sources/group/A1.h", "Sources/group/A2.h", "Sources/group/A3.h",
            "Sources/group/A1+Mock.h", "Sources/group/A2+Protected.h", "Sources/group/A4+Private.h",
        ])
        try createVersionFile(content: umbrellaContent, in: umbrellaPath)

        let manifest = ProjectDescription.Headers.allHeaders(
            from: .list([.glob("Sources/group/**", excluding: ["Sources/**/*+Mock.h"])]),
            umbrella: "Sources/Umbrella.h",
            private: "Sources/**/*+Private.h"
        )

        let model = try await XcodeGraph.Headers.from(
            manifest: manifest, generatorPaths: generatorPaths, productName: "TuistTestModule", fileSystem: fileSystem
        )

        #expect(model.public.sorted() == (try [
            "Sources/Umbrella.h", "Sources/group/A1.h", "Sources/group/A2.h", "Sources/group/A3.h",
        ].sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.private == (try ["Sources/group/A4+Private.h"]
                .map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.project.sorted() == (try ["Sources/group/A2+Protected.h"]
                .sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
    }

    @Test(.inTemporaryDirectory) func load_from_umbrella_withExcluding_withOutProject() async throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath, rootDirectory: temporaryPath)

        let umbrellaContent = """
        #import <Foundation/Foundation.h>
        FOUNDATION_EXPORT double TuistTestModuleVersionNumber;
        FOUNDATION_EXPORT const unsigned char TuistTestModuleVersionString[];
        #import <TuistTestModule/A1.h>
          #import <TuistTestModule/A2.h>
        #import "A3.h"
        """
        let umbrellaPath = temporaryPath.appending(try RelativePath(validating: "Sources/Umbrella.h"))

        try await TuistTest.createFiles([
            "Sources/group/A1.h", "Sources/group/A2.h", "Sources/group/A3.h",
            "Sources/group/A1+Mock.h", "Sources/group/A2+Protected.h", "Sources/group/A4+Private.h",
        ])
        try createVersionFile(content: umbrellaContent, in: umbrellaPath)

        let manifest = ProjectDescription.Headers.onlyHeaders(
            from: .list([.glob("Sources/group/**", excluding: ["Sources/**/*+Mock.h"])]),
            umbrella: "Sources/Umbrella.h",
            private: "Sources/**/*+Private.h"
        )

        let model = try await XcodeGraph.Headers.from(
            manifest: manifest, generatorPaths: generatorPaths, productName: "TuistTestModule", fileSystem: fileSystem
        )

        #expect(model.public.sorted() == (try [
            "Sources/Umbrella.h", "Sources/group/A1.h", "Sources/group/A2.h", "Sources/group/A3.h",
        ].sorted().map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.private == (try ["Sources/group/A4+Private.h"]
                .map { temporaryPath.appending(try RelativePath(validating: $0)) }))
        #expect(model.project.sorted() == [])
    }

    private func createVersionFile(content: String, in path: AbsolutePath) throws {
        let data = try #require(content.data(using: .utf8))
        try data.write(to: path.url, options: .atomic)
    }
}
