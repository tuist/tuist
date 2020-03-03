import Basic
import Foundation
import TuistSupport
import XCTest

@testable import TuistSupportTesting
@testable import TuistTemplate
@testable import TuistTemplateTesting

final class TemplateGeneratorTests: TuistTestCase {
    var subject: TemplateGenerator!
    var templateLoader: MockTemplateLoader!

    override func setUp() {
        super.setUp()
        templateLoader = MockTemplateLoader()
        subject = TemplateGenerator(templateLoader: templateLoader)
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
        templateLoader = nil
    }

    func test_directories_are_generated() throws {
        // Given
        let directories = [RelativePath("a"), RelativePath("a/b"), RelativePath("c")]
        templateLoader.loadTemplateStub = { _ in
            Template(description: "",
                     directories: directories)
        }
        let destinationPath = try temporaryPath()
        let expectedDirectories = directories.map(destinationPath.appending)

        // When
        try subject.generate(at: try temporaryPath(),
                             to: destinationPath,
                             attributes: [])

        // Then
        XCTAssertTrue(expectedDirectories.allSatisfy(FileHandler.shared.exists))
    }

    func test_directories_with_attributes() throws {
        // Given
        let name = "GenName"
        let bName = "BName"
        let defaultName = "defaultName"
        let directories = [RelativePath("{{ name }}"), RelativePath("{{ aName }}"), RelativePath("{{ bName }}")]
        templateLoader.loadTemplateStub = { _ in
            Template(description: "",
                     attributes: [
                         .required("name"),
                         .optional("aName", default: defaultName),
                         .optional("bName", default: ""),
                     ],
                     directories: directories)
        }
        let destinationPath = try temporaryPath()
        let expectedDirectories = [name, defaultName, bName].map(destinationPath.appending)

        // When
        try subject.generate(at: try temporaryPath(),
                             to: destinationPath,
                             attributes: ["--name", name, "--bName", bName])

        // Then
        XCTAssertTrue(expectedDirectories.allSatisfy(FileHandler.shared.exists))
    }

    func test_fails_when_required_attribute_not_provided() throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template(description: "",
                     attributes: [.required("required")])
        }

        // Then
        XCTAssertThrowsSpecific(try subject.generate(at: try temporaryPath(),
                                                     to: try temporaryPath(),
                                                     attributes: []),
                                TemplateGeneratorError.attributeNotFound("required"))
    }

    func test_files_are_generated() throws {
        // Given
        let files: [(path: RelativePath, contents: Template.Contents)] = [
            (path: RelativePath("a"), contents: .static("aContent")),
            (path: RelativePath("b"), contents: .static("bContent")),
        ]
        templateLoader.loadTemplateStub = { _ in
            Template(description: "",
                     files: files)
        }
        let destinationPath = try temporaryPath()
        let expectedFiles: [(AbsolutePath, String)] = files.compactMap {
            let content: String
            switch $0.contents {
            case let .static(staticContent):
                content = staticContent
            case .generated:
                XCTFail("Unexpected type")
                return nil
            }
            return (destinationPath.appending($0.path), content)
        }

        // When
        try subject.generate(at: try temporaryPath(),
                             to: destinationPath,
                             attributes: [])

        // Then
        try expectedFiles.forEach {
            XCTAssertEqual(try FileHandler.shared.readTextFile($0.0), $0.1)
        }
    }

    func test_files_are_generated_with_attributes() throws {
        // Given
        templateLoader.loadTemplateStub = { _ in
            Template(description: "",
                     attributes: [
                         .required("name"),
                         .required("contentName"),
                         .required("directoryName"),
                         .required("fileName"),
                     ],
                     files: [
                         (path: RelativePath("{{ name }}"), contents: .static("{{ contentName }}")),
                         (path: RelativePath("{{ directoryName }}/{{ fileName }}"), contents: .static("bContent")),
                     ],
                     directories: [RelativePath("{{ directoryName }}")])
        }
        let name = "test name"
        let contentName = "test content"
        let directoryName = "test directory"
        let fileName = "test file"
        let destinationPath = try temporaryPath()
        let expectedFiles: [(AbsolutePath, String)] = [
            (destinationPath.appending(component: name), contentName),
            (destinationPath.appending(components: directoryName, fileName), "bContent"),
        ]

        // When
        try subject.generate(at: try temporaryPath(),
                             to: destinationPath,
                             attributes: [
                                 "--name", name,
                                 "--contentName", contentName,
                                 "--directoryName", directoryName,
                                 "--fileName", fileName,
                             ])

        // Then
        try expectedFiles.forEach {
            XCTAssertEqual(try FileHandler.shared.readTextFile($0.0), $0.1)
        }
    }

    func test_generated_files() throws {
        // Given
        let sourcePath = try temporaryPath()
        let destinationPath = try temporaryPath()
        let name = "test name"
        let aContent = "test a content"
        let bContent = "test b content"
        templateLoader.loadTemplateStub = { _ in
            Template(description: "",
                     attributes: [.required("name")],
                     files: [
                         (path: RelativePath("a"), contents: .generated(sourcePath.appending(component: "a"))),
                         (path: RelativePath("b/{{ name }}"), contents: .generated(sourcePath.appending(components: "b"))),
                     ],
                     directories: [RelativePath("b")])
        }
        templateLoader.loadGenerateFileStub = { filePath, _ in
            if filePath == destinationPath.appending(components: "a") {
                return aContent
            } else if filePath == destinationPath.appending(components: "b") {
                return bContent
            } else {
                XCTFail("unexpected path \(filePath)")
                return ""
            }
        }
        let expectedFiles: [(AbsolutePath, String)] = [
            (destinationPath.appending(component: "a"), aContent),
            (destinationPath.appending(components: "b", name), bContent),
        ]

        // When
        try subject.generate(at: sourcePath,
                             to: destinationPath,
                             attributes: ["--name", name])

        // Then
        try expectedFiles.forEach {
            XCTAssertEqual(try FileHandler.shared.readTextFile($0.0), $0.1)
        }
    }

    func test_attributes_passed_to_generated_file() throws {
        // Given
        let sourcePath = try temporaryPath()
        let destinationPath = try temporaryPath()
        var parsedAttributes: [ParsedAttribute] = []
        templateLoader.loadGenerateFileStub = { filePath, attributes in
            if filePath == sourcePath.appending(component: "a") {
                parsedAttributes = attributes
            } else {
                XCTFail("unexpected path \(filePath)")
            }
            return ""
        }
        templateLoader.loadTemplateStub = { _ in
            Template(description: "",
                     attributes: [.required("name")],
                     files: [(path: RelativePath("a"),
                              contents: .generated(sourcePath.appending(component: "a")))])
        }
        let expectedParsedAttributes: [ParsedAttribute] = [ParsedAttribute(name: "name", value: "attribute name")]

        // When
        try subject.generate(at: sourcePath,
                             to: destinationPath,
                             attributes: ["--name", "attribute name"])

        // Then
        XCTAssertEqual(parsedAttributes, expectedParsedAttributes)
    }
}
