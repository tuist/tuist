import Foundation

struct XCTestPlan: Codable {
    struct TestTarget: Codable {
        let parallelizable: Bool?
        let target: TestTargetReference
    }

    struct TestTargetReference: Codable {
        let containerPath: String
        let identifier: String
        let name: String
    }

    let testTargets: [TestTarget]
}
