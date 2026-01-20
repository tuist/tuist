import Foundation
import Path

struct XCResultTestOutput: Codable {
    let devices: [Device]?
    let testNodes: [TestNode]
    let testPlanConfigurations: [TestPlanConfiguration]?
}

struct Device: Codable {
    let architecture: String?
    let deviceId: String?
    let deviceName: String?
    let modelName: String?
    let osBuildNumber: String?
    let osVersion: String?
    let platform: String?
}

struct TestNode: Codable {
    let children: [TestNode]?
    let name: String?
    let nodeIdentifier: String?
    let nodeIdentifierURL: String?
    let nodeType: String?
    let result: String?
    let duration: String?
    let durationInSeconds: Double?
}

struct TestPlanConfiguration: Codable {
    let configurationId: String?
    let configurationName: String?
}

struct TestFailure {
    let message: String
    let filePath: RelativePath?
    let lineNumber: Int
}
