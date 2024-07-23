import Foundation
import Path
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistScaffold
@testable import TuistSupportTesting

final class TemplateGeneratorTests: TuistTestCase {
    var subject: TemplateGenerator!

    override func setUp() {
        super.setUp()
        subject = TemplateGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_directories_are_generated() async throws {
        // Given
        let directories = [
            try RelativePath(validating: "a"),
            try RelativePath(validating: "a/b"),
            try RelativePath(validating: "c"),
        ]
        let destinationPath = try temporaryPath()
        let expectedDirectories = directories.map(destinationPath.appending)
        let items = try directories.map {
            Template.Item.test(path: try RelativePath(validating: $0.pathString + "/file.swift"))
        }

        let template = Template.test(items: items)

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: [:]
        )

        // Then
        XCTAssertTrue(expectedDirectories.allSatisfy(FileHandler.shared.exists))
    }

    func test_directories_with_attributes() async throws {
        // Given
        let directories = [
            try RelativePath(validating: "{{ name|lowercase }}"),
            try RelativePath(validating: "{{ aName }}"),
            try RelativePath(validating: "{{ name }}/{{ bName }}"),
        ]
        let items = try directories.map {
            Template.Item.test(path: try RelativePath(validating: $0.pathString + "/file.swift"))
        }
        let template = Template.test(items: items)
        let destinationPath = try temporaryPath()
        let expectedDirectories = [
            try RelativePath(validating: "test_name"),
            try RelativePath(validating: "test"),
            try RelativePath(validating: "test_name/nested_dir"),
        ].map(destinationPath.appending)

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: [
                "name": .string("Test_Name"),
                "aName": .string("test"),
                "bName": .string("nested_dir"),
            ]
        )

        // Then
        XCTAssertTrue(expectedDirectories.allSatisfy(FileHandler.shared.exists))
    }

    func test_files_are_generated() async throws {
        // Given
        let items: [Template.Item] = [
            Template.Item(path: try RelativePath(validating: "a"), contents: .string("aContent")),
            Template.Item(path: try RelativePath(validating: "b"), contents: .string("bContent")),
            Template.Item(path: try RelativePath(validating: ".gitkeep"), contents: .string("")),
        ]

        let template = Template.test(items: items)
        let destinationPath = try temporaryPath()
        let expectedFiles: [(AbsolutePath, String)] = items.compactMap {
            let content: String
            switch $0.contents {
            case let .string(staticContent):
                content = staticContent
            case .file, .directory:
                XCTFail("Unexpected type")
                return nil
            }
            return (destinationPath.appending($0.path), content)
        }

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: [:]
        )

        // Then
        for expectedFile in expectedFiles {
            XCTAssertEqual(try FileHandler.shared.readTextFile(expectedFile.0), expectedFile.1)
        }
    }

    func test_files_are_generated_with_attributes() async throws {
        // Given
        let sourcePath = try temporaryPath()
        let items = [
            Template.Item(path: try RelativePath(validating: "{{ name }}"), contents: .string("{{ contentName }}")),
            Template.Item(
                path: try RelativePath(validating: "{{ directoryName }}/{{ fileName }}"),
                contents: .string("bContent")
            ),
            Template.Item(
                path: try RelativePath(validating: "file"),
                contents: .file(sourcePath.appending(component: "{{ filePath }}"))
            ),
        ]
        let template = Template.test(items: items)
        let name = "test name"
        let contentName = "test content"
        let fileContent = "test file content"
        let directoryName = "test directory"
        let fileName = "test file"
        let filePath = "test file path"
        let destinationPath = try temporaryPath()
        try FileHandler.shared.write(fileContent, path: sourcePath.appending(component: filePath), atomically: true)
        let expectedFiles: [(AbsolutePath, String)] = [
            (destinationPath.appending(component: name), contentName),
            (destinationPath.appending(components: directoryName, fileName), "bContent"),
            (destinationPath.appending(component: filePath), fileContent),
        ]

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: [
                "name": .string(name),
                "contentName": .string(contentName),
                "directoryName": .string(directoryName),
                "fileName": .string(fileName),
                "filePath": .string(filePath),
            ]
        )

        // Then
        for expectedFile in expectedFiles {
            XCTAssertEqual(try FileHandler.shared.readTextFile(expectedFile.0), expectedFile.1)
        }
    }

    func test_rendered_files() async throws {
        // Given
        let sourcePath = try temporaryPath()
        let destinationPath = try temporaryPath()
        let name = "test name"
        let aContent = "test a content"
        let bContent = "test b content"
        let items = [
            Template.Item(
                path: try RelativePath(validating: "a/file"),
                contents: .file(sourcePath.appending(component: "testFile"))
            ),
            Template.Item(
                path: try RelativePath(validating: "b/{{ name }}/file"),
                contents: .file(sourcePath.appending(components: "bTestFile"))
            ),
        ]
        let template = Template.test(items: items)
        try FileHandler.shared.write(aContent, path: sourcePath.appending(component: "testFile"), atomically: true)
        try FileHandler.shared.write(bContent, path: sourcePath.appending(component: "bTestFile"), atomically: true)
        let expectedFiles: [(AbsolutePath, String)] = [
            (destinationPath.appending(components: "a", "file"), aContent),
            (destinationPath.appending(components: "b", name, "file"), bContent),
        ]

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: ["name": .string(name)]
        )

        // Then
        for expectedFile in expectedFiles {
            XCTAssertEqual(try FileHandler.shared.readTextFile(expectedFile.0), expectedFile.1)
        }
    }

    func test_file_rendered_with_attributes() async throws {
        // Given
        let sourcePath = try temporaryPath()
        let destinationPath = try temporaryPath()
        let expectedContents = "attribute name content"
        try FileHandler.shared.write(
            "{{ name }} content",
            path: sourcePath.appending(component: "a.stencil"),
            atomically: true
        )
        let template = Template.test(items: [Template.Item(
            path: try RelativePath(validating: "a"),
            contents: .file(sourcePath.appending(component: "a.stencil"))
        )])

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: ["name": .string("attribute name")]
        )

        // Then
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(destinationPath.appending(component: "a")),
            expectedContents
        )
    }

    func test_only_stencil_files_rendered() async throws {
        // Given
        let sourcePath = try temporaryPath()
        let destinationPath = try temporaryPath()
        let expectedRenderedContents = "attribute name content"
        let expectedUnrenderedContents = "{{ name }} content"
        try FileHandler.shared.write(
            "{{ name }} content",
            path: sourcePath.appending(component: "a.stencil"),
            atomically: true
        )
        try FileHandler.shared.write(
            "{{ name }} content",
            path: sourcePath.appending(component: "a.swift"),
            atomically: true
        )
        let template = Template.test(items: [
            Template.Item(
                path: try RelativePath(validating: "unrendered"),
                contents: .file(sourcePath.appending(component: "a.swift"))
            ),
            Template.Item(
                path: try RelativePath(validating: "rendered"),
                contents: .file(sourcePath.appending(component: "a.stencil"))
            ),
        ])

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: ["name": .string("attribute name")]
        )

        // Then
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(destinationPath.appending(component: "rendered")),
            expectedRenderedContents
        )
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(destinationPath.appending(component: "unrendered")),
            expectedUnrenderedContents
        )
    }

    func test_empty_stencil_files_are_skipped() async throws {
        // Given
        let sourcePath = try temporaryPath()
        let destinationPath = try temporaryPath()
        try FileHandler.shared.write(
            "   \n   ",
            path: sourcePath.appending(component: "b.stencil"),
            atomically: true
        )
        let template = Template.test(items: [
            Template.Item(
                path: try RelativePath(validating: "ignore"),
                contents: .file(sourcePath.appending(component: "b.stencil"))
            ),
        ])

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: ["name": .string("attribute name")]
        )

        // Then
        XCTAssertFalse(FileHandler.shared.exists(destinationPath.appending(component: "ignore")))
    }

    func test_copy_directory() async throws {
        // Given
        let sourcePath = try temporaryPath().appending(components: "folder")
        try FileHandler.shared.createFolder(sourcePath)

        let destinationPath = try temporaryPath()
        let expectedContentFile = "File's content"

        try FileHandler.shared.write(
            expectedContentFile,
            path: sourcePath.appending(component: "file1.txt"),
            atomically: true
        )

        let template = Template.test(items: [
            Template.Item(
                path: try RelativePath(validating: "destination"),
                contents: .directory(sourcePath)
            ),
        ])

        // When
        try await subject.generate(
            template: template,
            to: destinationPath,
            attributes: [:]
        )

        // Then
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(destinationPath.appending(components: "destination", "folder", "file1.txt")),
            expectedContentFile
        )
    }
}
