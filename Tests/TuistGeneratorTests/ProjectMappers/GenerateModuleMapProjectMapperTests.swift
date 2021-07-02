import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

public final class GenerateModuleMapProjectMapperTests: TuistUnitTestCase {
    var subject: GenerateModuleMapProjectMapper!

    override public func setUp() {
        super.setUp()
        subject = GenerateModuleMapProjectMapper(
            derivedDirectoryName: Constants.DerivedDirectory.name,
            moduleMapsDirectoryName: Constants.DerivedDirectory.moduleMaps
        )
    }

    override public func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map() throws {
        // Given
        let targetA = Target.test(name: "A", headers: .init(public: ["/a/public/header.h"], private: [], project: []))
        let targetB = Target.test(name: "B")
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        let expectedPath = RelativePath("Derived/ModuleMaps/A.modulemap")

        XCTAssertEqual(
            mappedProject,
            Project.test(
                targets: [
                    Target.test(
                        name: "A",
                        settings: Settings(base: ["MODULEMAP_FILE": .string(expectedPath.pathString)], configurations: [:]),
                        headers: .init(public: ["/a/public/header.h"], private: [], project: [])
                    ),
                    Target.test(name: "B"),
                ]
            )
        )
        XCTAssertEqual(
            sideEffects,
            [
                .file(FileDescriptor(
                    path: AbsolutePath("/Project/Derived/ModuleMaps/A.modulemap"),
                    contents: """
                    framework module A {
                        umbrella header "header.h"
                        export *
                        module * { export * }
                    }
                    """.data(using: .utf8)
                )),
            ]
        )
    }

    func test_map_when_modulemap_already_defined_does_nothing() throws {
        // Given
        let targetA = Target.test(
            name: "A",
            settings: Settings(base: ["MODULEMAP_FILE": "/path.modulemap"], configurations: [:]),
            headers: .init(public: ["/a/public/header.h"], private: [], project: [])
        )
        let targetB = Target.test(name: "B")
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(mappedProject, project)
        XCTAssertEqual(sideEffects, [])
    }

    func test_map_when_no_public_headers_does_nothing() throws {
        // Given
        let targetA = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(mappedProject, project)
        XCTAssertEqual(sideEffects, [])
    }

    func test_map_when_multiple_public_headers_does_nothing() throws {
        // Given
        let targetA = Target.test(
            name: "A",
            headers: .init(public: ["/a/public/header.h", "/another/public/header.h"], private: [], project: [])
        )
        let targetB = Target.test(name: "B")
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(mappedProject, project)
        XCTAssertEqual(sideEffects, [])
    }

    func test_map_when_public_header_matches_target_does_nothing() throws {
        // Given
        let targetA = Target.test(
            name: "A",
            headers: .init(public: ["/a/public/A.h"], private: [], project: [])
        )
        let targetB = Target.test(name: "B")
        let project = Project.test(targets: [targetA, targetB])

        // When
        let (mappedProject, sideEffects) = try subject.map(project: project)

        // Then
        XCTAssertEqual(mappedProject, project)
        XCTAssertEqual(sideEffects, [])
    }
}
