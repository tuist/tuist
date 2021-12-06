import Foundation
import TSCBasic
import TuistGraph
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

    func test_directories_are_generated() throws {
        // Given
        let directories = [RelativePath("a"), RelativePath("a/b"), RelativePath("c")]
        let destinationPath = try temporaryPath()
        let expectedDirectories = directories.map(destinationPath.appending)
        let items = directories.map {
            Template.Item.test(path: RelativePath($0.pathString + "/file.swift"))
        }

        let template = Template.test(items: items)

        // When
        try subject.generate(
            template: template,
            to: destinationPath,
            attributes: [:]
        )

        // Then
        XCTAssertTrue(expectedDirectories.allSatisfy(FileHandler.shared.exists))
    }

    func test_directories_with_attributes() throws {
        // Given
        let directories = [RelativePath("{{ name }}"), RelativePath("{{ aName }}"), RelativePath("{{ name }}/{{ bName }}")]
        let items = directories.map {
            Template.Item.test(path: RelativePath($0.pathString + "/file.swift"))
        }
        let template = Template.test(items: items)
        let destinationPath = try temporaryPath()
        let expectedDirectories = [
            RelativePath("test_name"),
            RelativePath("test"),
            RelativePath("test_name/nested_dir"),
        ].map(destinationPath.appending)

        // When
        try subject.generate(
            template: template,
            to: destinationPath,
            attributes: [
                "name": "test_name",
                "aName": "test",
                "bName": "nested_dir",
            ]
        )

        // Then
        XCTAssertTrue(expectedDirectories.allSatisfy(FileHandler.shared.exists))
    }

    func test_files_are_generated() throws {
        // Given
        let items: [Template.Item] = [
            Template.Item(path: RelativePath("a"), contents: .string("aContent")),
            Template.Item(path: RelativePath("b"), contents: .string("bContent")),
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
        try subject.generate(
            template: template,
            to: destinationPath,
            attributes: [:]
        )

        // Then
        try expectedFiles.forEach {
            XCTAssertEqual(try FileHandler.shared.readTextFile($0.0), $0.1)
        }
    }

    func test_files_are_generated_with_attributes() throws {
        // Given
        let sourcePath = try temporaryPath()
        let items = [
            Template.Item(path: RelativePath("{{ name }}"), contents: .string("{{ contentName }}")),
            Template.Item(path: RelativePath("{{ directoryName }}/{{ fileName }}"), contents: .string("bContent")),
            Template.Item(path: RelativePath("file"), contents: .file(sourcePath.appending(component: "{{ filePath }}"))),
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
        try subject.generate(
            template: template,
            to: destinationPath,
            attributes: [
                "name": name,
                "contentName": contentName,
                "directoryName": directoryName,
                "fileName": fileName,
                "filePath": filePath,
            ]
        )

        // Then
        try expectedFiles.forEach {
            XCTAssertEqual(try FileHandler.shared.readTextFile($0.0), $0.1)
        }
    }

    func test_rendered_files() throws {
        // Given
        let sourcePath = try temporaryPath()
        let destinationPath = try temporaryPath()
        let name = "test name"
        let aContent = "test a content"
        let bContent = "test b content"
        let items = [
            Template.Item(path: RelativePath("a/file"), contents: .file(sourcePath.appending(component: "testFile"))),
            Template.Item(
                path: RelativePath("b/{{ name }}/file"),
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
        try subject.generate(
            template: template,
            to: destinationPath,
            attributes: ["name": name]
        )

        // Then
        try expectedFiles.forEach {
            XCTAssertEqual(try FileHandler.shared.readTextFile($0.0), $0.1)
        }
    }

    func test_file_rendered_with_attributes() throws {
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
            path: RelativePath("a"),
            contents: .file(sourcePath.appending(component: "a.stencil"))
        )])

        // When
        try subject.generate(
            template: template,
            to: destinationPath,
            attributes: ["name": "attribute name"]
        )

        // Then
        XCTAssertEqual(
            try FileHandler.shared.readTextFile(destinationPath.appending(component: "a")),
            expectedContents
        )
    }

    func test_only_stencil_files_rendered() throws {
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
                path: RelativePath("unrendered"),
                contents: .file(sourcePath.appending(component: "a.swift"))
            ),
            Template.Item(
                path: RelativePath("rendered"),
                contents: .file(sourcePath.appending(component: "a.stencil"))
            ),
        ])

        // When
        try subject.generate(
            template: template,
            to: destinationPath,
            attributes: ["name": "attribute name"]
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

    func test_empty_stencil_files_are_skipped() throws {
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
                path: RelativePath("ignore"),
                contents: .file(sourcePath.appending(component: "b.stencil"))
            ),
        ])

        // When
        try subject.generate(
            template: template,
            to: destinationPath,
            attributes: ["name": "attribute name"]
        )

        // Then
        XCTAssertFalse(FileHandler.shared.exists(destinationPath.appending(component: "ignore")))
    }

    func test_copy_directory() throws {
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
                path: RelativePath("destination"),
                contents: .directory(sourcePath)
            ),
        ])

        // When
        try subject.generate(
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
