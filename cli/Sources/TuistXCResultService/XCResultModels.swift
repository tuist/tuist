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
    let title: String?

    struct CommandInvocationDetails: Codable {
        let emittedOutput: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Try to decode emittedOutput, but if it fails, use nil
            emittedOutput = try? container.decodeIfPresent(String.self, forKey: .emittedOutput)
        }

        private enum CodingKeys: String, CodingKey {
            case emittedOutput
        }
    }

    struct TestDetails: Codable {
        let emittedOutput: String?
        let runnablePath: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Try to decode emittedOutput, but if it fails, use nil
            emittedOutput = try? container.decodeIfPresent(String.self, forKey: .emittedOutput)
            runnablePath = try container.decodeIfPresent(String.self, forKey: .runnablePath)
        }

        private enum CodingKeys: String, CodingKey {
            case emittedOutput
            case runnablePath
        }
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

    /// Extract module durations by finding subsections with runnablePath in testDetails
    /// and extracting the module name from XCTest output pattern
    func extractModuleDurations(secondsToMilliseconds: (Double) -> Int) -> [String: Int] {
        var moduleDurations: [String: Int] = [:]
        extractModuleDurationsRecursive(into: &moduleDurations, secondsToMilliseconds: secondsToMilliseconds)
        return moduleDurations
    }

    private func extractModuleDurationsRecursive(into moduleDurations: inout [String: Int], secondsToMilliseconds: (Double) -> Int) {
        // Check if this section has a runnablePath and duration
        if let runnablePath = testDetails?.runnablePath,
           let duration = duration,
           let emittedOutput = testDetails?.emittedOutput,
           (runnablePath.hasSuffix(".app") || runnablePath.hasSuffix(".xctest") || runnablePath.contains("/xctest")) {

            // Extract module name from XCTest pattern: "-[ModuleName.ClassName testMethod]"
            let xcTestPattern = #"-\[([^.]+)\."#
            if let regex = try? NSRegularExpression(pattern: xcTestPattern, options: []),
               let match = regex.firstMatch(in: emittedOutput, options: [], range: NSRange(emittedOutput.startIndex..<emittedOutput.endIndex, in: emittedOutput)),
               let moduleRange = Range(match.range(at: 1), in: emittedOutput) {
                let moduleName = String(emittedOutput[moduleRange])
                if !moduleName.isEmpty {
                    let durationMs = secondsToMilliseconds(duration)
                    // Use the first (should be only) occurrence
                    if moduleDurations[moduleName] == nil {
                        moduleDurations[moduleName] = durationMs
                    }
                }
            }
        }

        // Recursively process subsections
        if let subsections = subsections {
            for subsection in subsections {
                subsection.extractModuleDurationsRecursive(into: &moduleDurations, secondsToMilliseconds: secondsToMilliseconds)
            }
        }
    }
}
