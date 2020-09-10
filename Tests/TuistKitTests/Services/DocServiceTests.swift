import Foundation
import TSCBasic
import TuistCore
import TuistDoc
import TuistDocTesting
import TuistSupport
import XCTest

@testable import TuistCoreTesting
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
        let path = AbsolutePath("/.")
        XCTAssertThrowsError(try subject.run(project: path, target: "CustomTarget", serve: false, port: 4040))
    }

    func test_doc_fail_missing_file() {
        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")
        mockGraph(targetName: targetName, atPath: path)
        fileHandler.stubExists = { _ in false }

        XCTAssertThrowsError(try subject.run(project: path, target: targetName, serve: false, port: 4040))
    }

    func test_doc_success() {
        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")

        mockGraph(targetName: targetName, atPath: path)
        fileHandler.stubExists = { _ in true }

        XCTAssertThrowsError(try subject.run(project: path, target: targetName, serve: false, port: 4040))
    }

    func test_server_error() {
        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")

        mockGraph(targetName: targetName, atPath: path)
        fileHandler.stubExists = { _ in true }

        swiftDocServer.stubError = MockSwiftDocServer.MockError.mockError
        XCTAssertThrowsError(try subject.run(project: path, target: targetName, serve: true, port: 4040))
    }

    private func mockGraph(targetName _: String, atPath path: AbsolutePath) {
        let project = Project.test()
        let target = Target.test(name: "CustomTarget")
        let targetNode = TargetNode(project: project, target: target, dependencies: [])
        let graph = Graph.test(targets: [path: [targetNode]])

        projectGenerator.loadProjectStub = { _ in
            (Project.test(), graph, [])
        }
    }
}
