import Foundation

// MARK: - XCResult Test Output Models

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

// MARK: - Action Log Models

struct ActionLogSection: Codable {
    let subsections: [ActionLogSection]?
    let commandInvocationDetails: CommandInvocationDetails?
    let testDetails: TestDetails?
    let duration: Double?

    struct CommandInvocationDetails: Codable {
        let emittedOutput: String?
    }

    struct TestDetails: Codable {
        let emittedOutput: String?
    }
}

// Helper to recursively search for emittedOutput
extension ActionLogSection {
    func collectEmittedOutputs() -> [String] {
        var outputs: [String] = []

        // Collect from commandInvocationDetails
        if let emittedOutput = commandInvocationDetails?.emittedOutput, !emittedOutput.isEmpty {
            outputs.append(emittedOutput)
        }

        // Collect from testDetails
        if let emittedOutput = testDetails?.emittedOutput, !emittedOutput.isEmpty {
            outputs.append(emittedOutput)
        }

        // Recursively collect from subsections
        if let subsections = subsections {
            for subsection in subsections {
                outputs.append(contentsOf: subsection.collectEmittedOutputs())
            }
        }

        return outputs
    }
}
