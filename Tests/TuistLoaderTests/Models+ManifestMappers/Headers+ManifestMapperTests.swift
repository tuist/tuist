import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistSupportTesting

final class HeadersManifestMapperTests: TuistUnitTestCase {
    func test_from() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Sources/public/A1.h",
            "Sources/public/A1.m",
            "Sources/public/A2.h",
            "Sources/public/A2.m",

            "Sources/private/B1.h",
            "Sources/private/B1.m",
            "Sources/private/B2.h",
            "Sources/private/B2.m",

            "Sources/project/C1.h",
            "Sources/project/C1.m",
            "Sources/project/C2.h",
            "Sources/project/C2.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: "Sources/public/**",
            private: "Sources/private/**",
            project: "Sources/project/**"
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA"
        )

        // Then
        XCTAssertEqual(model.public, [
            "Sources/public/A1.h",
            "Sources/public/A2.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
            "Sources/private/B1.h",
            "Sources/private/B2.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project, [
            "Sources/project/C1.h",
            "Sources/project/C2.h",
        ].map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_from_when_array() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Sources/public/A/A1.h",
            "Sources/public/A/A1.m",
            "Sources/public/B/B1.h",
            "Sources/public/B/B1.m",

            "Sources/private/C/C1.h",
            "Sources/private/C/C1.m",
            "Sources/private/D/D1.h",
            "Sources/private/D/D1.m",

            "Sources/project/E/E1.h",
            "Sources/project/E/E1.m",
            "Sources/project/F/F1.h",
            "Sources/project/F/F1.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: ["Sources/public/A/*.h", "Sources/public/B/*.h"],
            private: ["Sources/private/C/*.h", "Sources/private/D/*.h"],
            project: ["Sources/project/E/*.h", "Sources/project/F/*.h"]
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA"
        )

        // Then
        XCTAssertEqual(model.public, [
            "Sources/public/A/A1.h",
            "Sources/public/B/B1.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
            "Sources/private/C/C1.h",
            "Sources/private/D/D1.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project, [
            "Sources/project/E/E1.h",
            "Sources/project/F/F1.h",
        ].map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_from_when_array_and_string() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Sources/public/A/A1.h",
            "Sources/public/A/A1.m",

            "Sources/project/C/C1.h",
            "Sources/project/C/C1.m",
            "Sources/project/D/D1.h",
            "Sources/project/D/D1.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: "Sources/public/A/*.h",
            project: ["Sources/project/C/*.h", "Sources/project/D/*.h"]
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA"
        )

        // Then
        XCTAssertEqual(model.public, [
            "Sources/public/A/A1.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project, [
            "Sources/project/C/C1.h",
            "Sources/project/D/D1.h",
        ].map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_from_and_excluding() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Sources/public/A1.h",
            "Sources/public/A1.m",
            "Sources/public/A2.h",
            "Sources/public/A2.m",

            "Sources/private/B1.h",
            "Sources/private/B1.m",
            "Sources/private/B2.h",
            "Sources/private/B2.m",

            "Sources/project/C1.h",
            "Sources/project/C1.m",
            "Sources/project/C2.h",
            "Sources/project/C2.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: .list([.glob("Sources/public/**", excluding: "Sources/public/A2.h")]),
            private: .list([.glob("Sources/private/**", excluding: "Sources/private/B1.h")]),
            project: "Sources/project/**"
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA"
        )

        // Then
        XCTAssertEqual(model.public, [
            "Sources/public/A1.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
            "Sources/private/B2.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project, [
            "Sources/project/C1.h",
            "Sources/project/C2.h",
        ].map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_from_and_excluding_same_folder() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Sources/A1.h",
            "Sources/A1.m",
            "Sources/A2.h",
            "Sources/A2.m",

            "Sources/A1+Project.h",
            "Sources/A1+Project.m",
            "Sources/A2+Protected.h",
            "Sources/A2+Protected.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: .list([.glob("Sources/**", excluding: ["Sources/*+Protected.h", "Sources/*+Project.h"])]),
            private: nil,
            project: ["Sources/*+Protected.h", "Sources/*+Project.h"]
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA"
        )

        // Then
        XCTAssertEqual(model.public, [
            "Sources/A1.h",
            "Sources/A2.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project.sorted(), [
            "Sources/A1+Project.h",
            "Sources/A2+Protected.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_from_and_excluding_in_nested_folder() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Sources/group/A1.h",
            "Sources/group/A1.m",
            "Sources/group/A2.h",
            "Sources/group/A2.m",

            "Sources/group/A1+Project.h",
            "Sources/group/A1+Project.m",
            "Sources/group/A2+Protected.h",
            "Sources/group/A2+Protected.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: .list([.glob("Sources/**", excluding: ["Sources/**/*+Protected.h", "Sources/**/*+Project.h"])]),
            private: nil,
            project: ["Sources/**/*+Protected.h", "Sources/**/*+Project.h"]
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA"
        )

        // Then
        XCTAssertEqual(model.public, [
            "Sources/group/A1.h",
            "Sources/group/A2.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project.sorted(), [
            "Sources/group/A1+Project.h",
            "Sources/group/A2+Protected.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_exclusionRule_projectExcludesPrivateAndPublic() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Sources/group/A1.h",
            "Sources/group/A1.m",
            "Sources/group/A1+Project.h",
            "Sources/group/A1+Project.m",
            "Sources/group/A2.h",
            "Sources/group/A2.m",
            "Sources/group/A2+Protected.h",
            "Sources/group/A2+Protected.m",
            "Sources/group/A3.h",
            "Sources/group/A3.m",
            "Sources/group/A4+Private.h",
            "Sources/group/A4+Private.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: .list([
                .glob(
                    "Sources/**",
                    excluding: [
                        "Sources/**/*+Protected.h",
                        "Sources/**/*+Project.h",
                        "Sources/**/*+Private.h",
                    ]
                ),
            ]),
            private: ["Sources/**/*+Private.h"],
            project: ["Sources/**"],
            exclusionRule: .projectExcludesPrivateAndPublic
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA"
        )

        // Then
        XCTAssertEqual(model.public, [
            "Sources/group/A1.h",
            "Sources/group/A2.h",
            "Sources/group/A3.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
            "Sources/group/A4+Private.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project.sorted(), [
            "Sources/group/A1+Project.h",
            "Sources/group/A2+Protected.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_exclusionRule_publicExcludesPrivateAndProject() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)
        try createFiles([
            "Sources/group/A1.h",
            "Sources/group/A1.m",
            "Sources/group/A1+Project.h",
            "Sources/group/A1+Project.m",
            "Sources/group/A2.h",
            "Sources/group/A2.m",
            "Sources/group/A2+Protected.h",
            "Sources/group/A2+Protected.m",
            "Sources/group/A3.h",
            "Sources/group/A3.m",
            "Sources/group/A4+Private.h",
            "Sources/group/A4+Private.m",
        ])

        let manifest: ProjectDescription.Headers = .headers(
            public: ["Sources/**"],
            private: ["Sources/**/*+Private.h"],
            project: [
                "Sources/**/*+Protected.h",
                "Sources/**/*+Project.h",
            ],
            exclusionRule: .publicExcludesPrivateAndProject
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "ModuleA"
        )

        // Then
        XCTAssertEqual(model.public, [
            "Sources/group/A1.h",
            "Sources/group/A2.h",
            "Sources/group/A3.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
            "Sources/group/A4+Private.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project.sorted(), [
            "Sources/group/A1+Project.h",
            "Sources/group/A2+Protected.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_load_from_umbrella() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)

        let umbrellaContent = """
        #import <Foundation/Foundation.h>

        //! Project version number for TuistTestModule.
        FOUNDATION_EXPORT double TuistTestModuleVersionNumber;

        //! Project version string for TuistTestModule.
        FOUNDATION_EXPORT const unsigned char TuistTestModuleVersionString[];

        // In this header, you should import all the public headers of your framework using statements like #import <TuistTestModule/PublicHeader.h>

        #import <TuistTestModule/A1.h>
        #import <TuistTestModule/A2.h>
        #import "A3.h" // to test modules with legacy format
        #import <TuistTestModule/A2+Protected.h> // to test modules, where some protected files became public
        #import <UIKit/A4+Private.h> // to test incorrect module
        """
        let umbrellaPath = temporaryPath.appending(RelativePath("Sources/Umbrella.h"))

        try createFiles([
            "Sources/group/A1.h",
            "Sources/group/A2.h",
            "Sources/group/A3.h",
            "Sources/group/A1+Project.h",
            "Sources/group/A2+Protected.h",
            "Sources/group/A4+Private.h",
        ])
        try createVersionFile(content: umbrellaContent, in: umbrellaPath)

        let manifest = ProjectDescription.Headers.allHeaders(
            from: "Sources/**",
            umbrella: "Sources/Umbrella.h"
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "TuistTestModule"
        )

        // Then
        XCTAssertEqual(model.public.sorted(), [
            "Sources/Umbrella.h",
            "Sources/group/A1.h",
            "Sources/group/A2.h",
            "Sources/group/A3.h",
            "Sources/group/A2+Protected.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project.sorted(), [
            "Sources/group/A1+Project.h",
            "Sources/group/A4+Private.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_load_from_umbrella_withExcluding() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)

        let umbrellaContent = """
        #import <Foundation/Foundation.h>

        //! Project version number for TuistTestModule.
        FOUNDATION_EXPORT double TuistTestModuleVersionNumber;

        //! Project version string for TuistTestModule.
        FOUNDATION_EXPORT const unsigned char TuistTestModuleVersionString[];

        // In this header, you should import all the public headers of your framework using statements like #import <TuistTestModule/PublicHeader.h>

        #import <TuistTestModule/A1.h>
        #import <TuistTestModule/A2.h>
        #import "A3.h" // to test modules with legacy format
        """
        let umbrellaPath = temporaryPath.appending(RelativePath("Sources/Umbrella.h"))

        try createFiles([
            "Sources/group/A1.h",
            "Sources/group/A2.h",
            "Sources/group/A3.h",
            "Sources/group/A1+Mock.h",
            "Sources/group/A2+Protected.h",
            "Sources/group/A4+Private.h",
        ])
        try createVersionFile(content: umbrellaContent, in: umbrellaPath)

        let manifest = ProjectDescription.Headers.allHeaders(
            from: .list([.glob(
                "Sources/group/**",
                excluding: [
                    "Sources/**/*+Mock.h",
                ]
            )]),
            umbrella: "Sources/Umbrella.h",
            private: "Sources/**/*+Private.h"
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "TuistTestModule"
        )

        // Then
        XCTAssertEqual(model.public.sorted(), [
            "Sources/Umbrella.h", // should be added anyway
            "Sources/group/A1.h",
            "Sources/group/A2.h",
            "Sources/group/A3.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
            "Sources/group/A4+Private.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project.sorted(), [
            "Sources/group/A2+Protected.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })
    }

    func test_load_from_umbrella_withExcluding_withOutProject() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let generatorPaths = GeneratorPaths(manifestDirectory: temporaryPath)

        let umbrellaContent = """
        #import <Foundation/Foundation.h>

        //! Project version number for TuistTestModule.
        FOUNDATION_EXPORT double TuistTestModuleVersionNumber;

        //! Project version string for TuistTestModule.
        FOUNDATION_EXPORT const unsigned char TuistTestModuleVersionString[];

        // In this header, you should import all the public headers of your framework using statements like #import <TuistTestModule/PublicHeader.h>

        #import <TuistTestModule/A1.h>
        #import <TuistTestModule/A2.h>
        #import "A3.h" // to test modules with legacy format
        """
        let umbrellaPath = temporaryPath.appending(RelativePath("Sources/Umbrella.h"))

        try createFiles([
            "Sources/group/A1.h",
            "Sources/group/A2.h",
            "Sources/group/A3.h",
            "Sources/group/A1+Mock.h",
            "Sources/group/A2+Protected.h",
            "Sources/group/A4+Private.h",
        ])
        try createVersionFile(content: umbrellaContent, in: umbrellaPath)

        let manifest = ProjectDescription.Headers.onlyHeaders(
            from: .list([.glob(
                "Sources/group/**",
                excluding: [
                    "Sources/**/*+Mock.h",
                ]
            )]),
            umbrella: "Sources/Umbrella.h",
            private: "Sources/**/*+Private.h"
        )

        // When
        let model = try TuistGraph.Headers.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            productName: "TuistTestModule"
        )

        // Then
        XCTAssertEqual(model.public.sorted(), [
            "Sources/Umbrella.h", // should be added anyway
            "Sources/group/A1.h",
            "Sources/group/A2.h",
            "Sources/group/A3.h",
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.private, [
            "Sources/group/A4+Private.h",
        ].map { temporaryPath.appending(RelativePath($0)) })

        XCTAssertEqual(model.project.sorted(), [
        ].sorted().map { temporaryPath.appending(RelativePath($0)) })
    }

    private func createVersionFile(content: String, in path: AbsolutePath) throws {
        let data = try XCTUnwrap(content.data(using: .utf8))
        try data.write(to: path.url, options: .atomic)
    }
}
