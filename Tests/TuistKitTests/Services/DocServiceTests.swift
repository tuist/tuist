import Foundation
import TSCBasic
import TuistCore
import TuistDocTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistDoc
@testable import TuistKit
@testable import TuistSupportTesting

final class TuistDocServiceTests: TuistUnitTestCase {
    var subject: DocService!

    var generator: MockGenerator!
    var swiftDocController: MockSwiftDocController!
    var opener: MockOpener!
    var swiftDocServer: MockSwiftDocServer!
    var semaphore: MockSemaphore!

    override func setUp() {
        super.setUp()

        generator = MockGenerator()
        swiftDocController = MockSwiftDocController()
        opener = MockOpener()
        swiftDocServer = MockSwiftDocServer()
        semaphore = MockSemaphore()
        MockSwiftDocServer.stubBaseURL = "http://tuist.io"

        fileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })

        subject = DocService(generator: generator,
                             swiftDocController: swiftDocController,
                             swiftDocServer: swiftDocServer,
                             fileHandler: fileHandler,
                             opener: opener,
                             semaphore: semaphore)
    }

    override func tearDown() {
        super.tearDown()

        generator = nil
        swiftDocController = nil
        opener = nil
        swiftDocServer = nil
        subject = nil
    }

    func test_doc_fail_missing_target() {
        // Given
        let path = AbsolutePath("/.")

        // When / Then
        XCTAssertThrowsSpecific(try subject.run(project: path, target: "CustomTarget"),
                                DocServiceError.targetNotFound(name: "CustomTarget"))
    }

    func test_doc_fail_missing_file() {
        // Given

        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")
        mockGraph(targetName: targetName, atPath: path)
        swiftDocController.generateStub = { _, _, _, _, _ in }

        fileHandler.stubExists = { _ in false }

        // When / Then
        XCTAssertThrowsSpecific(try subject.run(project: path, target: targetName),
                                DocServiceError.documentationNotGenerated)
    }

    func test_doc_success() throws {
        // Given

        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")

        mockGraph(targetName: targetName, atPath: path)
        swiftDocController.generateStub = { _, _, _, _, _ in }
        fileHandler.stubExists = { _ in true }

        // When
        try subject.run(project: path, target: targetName)

        // Then
        XCTAssertTrue(opener.openCallCount == 1)
        XCTAssertTrue(semaphore.waitWasCalled)
        XCTAssertPrinterContains(
            "Opening the documentation. Press",
            at: .notice,
            ==
        )
    }

    func test_server_error() {
        // Given
        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")

        mockGraph(targetName: targetName, atPath: path)
        fileHandler.stubExists = { _ in true }
        swiftDocController.generateStub = { _, _, _, _, _ in }
        swiftDocServer.stubError = SwiftDocServerError.unableToStartServer(at: 4040)

        // When / Then
        XCTAssertThrowsSpecific(try subject.run(project: path, target: targetName),
                                SwiftDocServerError.unableToStartServer(at: 4040))
    }

    private func mockGraph(targetName: String, atPath path: AbsolutePath) {
        let project = Project.test(
            path: path
        )
        let target = Target.test(name: targetName)
        let targetNode = TargetNode(project: project, target: target, dependencies: [])
        let graph = Graph.test(
            projects: [project],
            targets: [path: [targetNode]]
        )

        generator.loadStub = { _ in
            graph
        }
    }
}

final class MockSemaphore: Semaphoring {
    var waitWasCalled: Bool = false
    func wait() {
        waitWasCalled = true
    }
}
