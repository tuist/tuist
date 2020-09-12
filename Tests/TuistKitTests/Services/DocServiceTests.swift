import Foundation
import TSCBasic
import TuistCore
import TuistDocTesting
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistDoc
@testable import TuistKit
@testable import TuistSupportTesting

final class TuistDocServiceTests: TuistUnitTestCase {
    var subject: DocService!

    var projectGenerator: MockProjectGenerator!
    var swiftDocController: MockSwiftDocController!
    var opener: MockOpener!
    var swiftDocServer: MockSwiftDocServer!

    override func setUp() {
        super.setUp()

        projectGenerator = MockProjectGenerator()
        swiftDocController = MockSwiftDocController()
        opener = MockOpener()
        swiftDocServer = MockSwiftDocServer()
        swiftDocServer.stubBaseURL = "http://tuist.io"

        fileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })

        subject = DocService(projectGenerator: projectGenerator,
                             swiftDocController: swiftDocController,
                             swiftDocServer: swiftDocServer,
                             fileHandler: fileHandler)
    }

    override func tearDown() {
        super.tearDown()

        projectGenerator = nil
        swiftDocController = nil
        opener = nil
        swiftDocServer = nil
        subject = nil
    }

    func test_doc_fail_missing_target() {
        // Given
        let path = AbsolutePath("/.")

        // When / Then
        XCTAssertThrowsSpecific(try subject.run(project: path, target: "CustomTarget", serve: false, port: 4040),
                                DocService.Error.targetNotFound(name: "CustomTarget"))
    }

    func test_doc_fail_missing_file() {
        // Given

        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")
        mockGraph(targetName: targetName, atPath: path)
        swiftDocController.generateStub = { _, _, _, _, _ in }

        fileHandler.stubExists = { _ in false }

        // When / Then
        XCTAssertThrowsSpecific(try subject.run(project: path, target: targetName, serve: false, port: 4040),
                                DocService.Error.documentationNotGenerated)
    }

    func test_doc_success() throws {
        // Given

        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")

        mockGraph(targetName: targetName, atPath: path)
        swiftDocController.generateStub = { _, _, _, _, _ in }
        fileHandler.stubExists = { _ in true }

        // When
        try subject.run(project: path, target: targetName, serve: false, port: 4040)

        // Then
        XCTAssertPrinterContains(
            "You can find the documentation at",
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
        swiftDocServer.stubError = SwiftDocServer.Error.unableToStartServer(at: 4040)

        // When / Then
        XCTAssertThrowsSpecific(try subject.run(project: path, target: targetName, serve: true, port: 4040),
                                SwiftDocServer.Error.unableToStartServer(at: 4040))
    }

    private func mockGraph(targetName: String, atPath path: AbsolutePath) {
        let project = Project.test()
        let target = Target.test(name: targetName)
        let targetNode = TargetNode(project: project, target: target, dependencies: [])
        let graph = Graph.test(targets: [path: [targetNode]])

        projectGenerator.loadProjectStub = { _ in
            (Project.test(), graph, [])
        }
    }
}
