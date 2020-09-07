import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistDocTesting
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
        XCTAssertThrowsError(try subject.run(path: path, target: "CustomTarget"))
    }

    func test_doc_fail_missing_file() {
        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")
        mockGraph(targetName: targetName, atPath: path)
        fileHandler.pathExistsStub = false

        XCTAssertThrowsError(try subject.run(path: path, target: targetName))
    }

    func test_doc_success() {
        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")

        mockGraph(targetName: targetName, atPath: path)
        fileHandler.pathExistsStub = true

        try! subject.run(path: path, target: targetName)
    }

    func test_server_error() {
        let targetName = "CustomTarget"
        let path = AbsolutePath("/.")

        mockGraph(targetName: targetName, atPath: path)
        fileHandler.pathExistsStub = true

        swiftDocServer.stubError = MockSwiftDocServer.MockError.mockError

        XCTAssertThrowsError(try subject.run(path: path, target: targetName))
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
