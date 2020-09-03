import Foundation
import TuistSupport
import XCTest
import TSCBasic
import TuistCore

@testable import TuistKit
@testable import TuistSupportTesting
@testable import TuistDocTesting
@testable import TuistCoreTesting

final class TuistDocServiceTests: TuistUnitTestCase {
    var subject: DocService!
    
    var projectGenerator: MockProjectGenerator!
    var swiftDocController: MockSwiftDocController!
    var opener: MockOpener!
    
    override func setUp() {
        super.setUp()
        
        projectGenerator = MockProjectGenerator()
        swiftDocController = MockSwiftDocController()
        opener = MockOpener()
        fileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })
        
        subject = DocService(projectGenerator: projectGenerator,
                             swiftDocController: swiftDocController,
                             opener: opener,
                             fileHandler: fileHandler)
    }
    
    override func tearDown() {
        super.tearDown()
        
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
    
    private func mockGraph(targetName: String, atPath path: AbsolutePath) {
        let project = Project.test()
        let target = Target.test(name: "CustomTarget")
        let targetNode = TargetNode(project: project, target: target, dependencies: [])
        let graph = Graph.test(targets: [path: [targetNode]])
        
        projectGenerator.loadProjectStub = { path in
            return (Project.test(), graph, [])
        }
    }
}

