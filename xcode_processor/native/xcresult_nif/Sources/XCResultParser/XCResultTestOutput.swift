import Foundation
import Path

struct XCResultTestOutput: Codable, Sendable {
    let devices: [Device]?
    let testNodes: [TestNode]
    let testPlanConfigurations: [TestPlanConfiguration]?
}

struct Device: Codable, Sendable {
    let architecture: String?
    let deviceId: String?
    let deviceName: String?
    let modelName: String?
    let osBuildNumber: String?
    let osVersion: String?
    let platform: String?
}

struct TestNode: Codable, Sendable {
    let children: [TestNode]?
    let name: String?
    let nodeIdentifier: String?
    let nodeIdentifierURL: String?
    let nodeType: String?
    let result: String?
    let duration: String?
    let durationInSeconds: Double?
}

struct TestPlanConfiguration: Codable, Sendable {
    let configurationId: String?
    let configurationName: String?
}

struct TestFailure: Sendable {
    let message: String
    let filePath: RelativePath?
    let lineNumber: Int
}
