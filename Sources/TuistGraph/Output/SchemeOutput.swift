import Foundation

/// The structure defining the output schema of an Xcode scheme.
public struct SchemeOutput: Codable, Equatable {
    
    /// The name of the scheme.
    public let name: String
    
    /// The targets that can be tested via this scheme.
    public let testActionTargets: [String]?
    
    public init(name: String, testActionTargets: [String]? = nil) {
        self.name = name
        self.testActionTargets = testActionTargets
    }
    
    /// Factory function to convert an internal graph scheme to the output type.
    public static func from(_ scheme: Scheme) -> SchemeOutput {
        var testTargets = [String]()
        if let testAction = scheme.testAction {
            for testTarget in testAction.targets {
                testTargets.append(testTarget.target.name)
            }
        }

        return SchemeOutput(name: scheme.name, testActionTargets: testTargets)
    }
}
